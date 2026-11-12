import AppKit
import ApplicationServices
import CoreGraphics

extension KeyModifiers {
    init(_ flags: CGEventFlags) {
        var modifiers: KeyModifiers = []
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        self = modifiers
    }
}

/// The session event tap that sees media keys before macOS does.
///
/// The callback runs on the main thread (the tap's source sits on the main run
/// loop) and must stay trivial: decode, ask `onEvent`, return. macOS disables
/// taps that stall, and a stalled tap holds up input for the whole session.
@MainActor
final class MediaKeyTap {
    enum StopReason {
        /// Accessibility trust went away while the tap was installed.
        case trustLost
    }

    /// `NX_SYSDEFINED`. `CGEventType` has no case for it.
    private static let systemDefinedEventType: UInt32 = 14
    private static let healthCheckInterval: TimeInterval = 5
    private static let trustCheckInterval: TimeInterval = 2

    /// Returns true to consume the event. Called for media key events only.
    var onEvent: ((MediaKeyEvent) -> Bool)?
    /// Called when the tap removes itself. Not called for `stop()`.
    var onStopped: ((StopReason) -> Void)?

    private let isTrusted: () -> Bool
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var healthTimer: Timer?
    private var trustTimer: Timer?
    private var wakeObserver: NSObjectProtocol?

    var isRunning: Bool { port != nil }

    init(isTrusted: @escaping () -> Bool = { AXIsProcessTrusted() }) {
        self.isTrusted = isTrusted
    }

    /// Installs the tap. Returns false when macOS refuses (no Accessibility trust).
    @discardableResult
    func start() -> Bool {
        guard port == nil else { return true }
        guard isTrusted() else { return false }

        let mask = CGEventMask(1) << CGEventMask(Self.systemDefinedEventType)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: mediaKeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            Log.tap.error("CGEvent.tapCreate failed")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        self.source = source

        healthTimer = makeTimer(every: Self.healthCheckInterval) { $0.checkHealth() }
        trustTimer = makeTimer(every: Self.trustCheckInterval) { $0.checkTrust() }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkHealth() }
        }

        Log.tap.notice("Event tap installed")
        return true
    }

    func stop() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(port)
        self.port = nil
        source = nil

        healthTimer?.invalidate()
        healthTimer = nil
        trustTimer?.invalidate()
        trustTimer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
        Log.tap.notice("Event tap removed")
    }

    // MARK: - Keeping the tap alive, and knowing when to let go

    private func makeTimer(
        every interval: TimeInterval, _ action: @escaping @MainActor (MediaKeyTap) -> Void
    ) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                if let self { action(self) }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    private func checkHealth() {
        guard let port, !CGEvent.tapIsEnabled(tap: port) else { return }
        // Losing trust also disables the tap; in that case let go instead.
        guard isTrusted() else {
            checkTrust()
            return
        }
        CGEvent.tapEnable(tap: port, enable: true)
        Log.tap.notice("Event tap was disabled; re-enabled by health check")
    }

    /// A live tap in a process that lost trust can stall input system-wide,
    /// so it is removed the moment the loss is noticed.
    private func checkTrust() {
        guard port != nil, !isTrusted() else { return }
        Log.tap.notice("Accessibility trust lost; removing event tap")
        stop()
        onStopped?(.trustLost)
    }

    // MARK: - Callback

    /// Returns true to consume the event.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port, isTrusted() {
                CGEvent.tapEnable(tap: port, enable: true)
                let byTimeout = type == .tapDisabledByTimeout
                Log.tap.notice(
                    "Event tap disabled by \(byTimeout ? "timeout" : "user input", privacy: .public); re-enabled")
            } else {
                // Not from inside the tap's own callback: tear down on the next turn.
                DispatchQueue.main.async { [weak self] in self?.checkTrust() }
            }
            return false
        }

        guard type.rawValue == Self.systemDefinedEventType,
              let onEvent,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.type == .systemDefined,
              Int(nsEvent.subtype.rawValue) == MediaKeyEvent.auxControlButtonsSubtype
        else { return false }

        let data1 = nsEvent.data1
        let flags = event.flags
        guard let keyEvent = MediaKeyEvent(
            subtype: MediaKeyEvent.auxControlButtonsSubtype,
            data1: data1,
            modifiers: KeyModifiers(flags))
        else { return false }

        let consume = onEvent(keyEvent)
        Log.trace {
            "key \(keyEvent.key) \(keyEvent.isDown ? "down" : "up") repeat=\(keyEvent.isRepeat) "
                + "data1=0x\(String(data1, radix: 16)) flags=0x\(String(flags.rawValue, radix: 16)) "
                + "modifiers=\(keyEvent.modifiers.rawValue) -> \(consume ? "consumed" : "passed through")"
        }
        return consume
    }
}

private func mediaKeyTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    // The tap's run loop source is on the main run loop, so this is the main thread.
    let consume = MainActor.assumeIsolated {
        Unmanaged<MediaKeyTap>.fromOpaque(userInfo).takeUnretainedValue()
            .handle(type: type, event: event)
    }
    return consume ? nil : Unmanaged.passUnretained(event)
}
