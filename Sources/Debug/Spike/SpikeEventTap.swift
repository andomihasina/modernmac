#if DEBUG
import AppKit
import CoreGraphics

/// Phase 0 spike tap. Used only from the main thread: the tap's run loop
/// source is added to the main run loop, so the callback arrives there too.
final class SpikeEventTap {
    enum Mode: String {
        case listen = "log only"
        case consume = "consume and handle"
    }

    private static let systemDefinedType: UInt32 = 14  // NX_SYSDEFINED
    private static let auxControlButtonsSubtype = 8    // NX_SUBTYPE_AUX_CONTROL_BUTTONS

    // Key codes from IOKit/hidsystem/ev_keymap.h.
    private static let keyNames: [Int: String] = [
        0: "soundUp", 1: "soundDown", 2: "brightnessUp", 3: "brightnessDown", 7: "mute",
        16: "play", 17: "next", 18: "previous", 19: "fast", 20: "rewind",
        21: "illuminationUp", 22: "illuminationDown", 23: "illuminationToggle",
    ]

    private(set) var mode: Mode?
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    /// Keys whose key-down we consumed, so the matching key-up is consumed too.
    private var consumedKeys: Set<Int> = []

    var isInstalled: Bool { port != nil }
    var isEnabled: Bool { port.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    func install(_ mode: Mode) -> Bool {
        remove()

        // Listen mode also watches plain key events so brightness keys that
        // arrive as key codes 144/145 show up. Consume mode mirrors the tap we
        // intend to ship: system-defined events only.
        var mask: CGEventMask = 1 << CGEventMask(Self.systemDefinedType)
        if mode == .listen {
            mask |= 1 << CGEventMask(CGEventType.keyDown.rawValue)
            mask |= 1 << CGEventMask(CGEventType.keyUp.rawValue)
        }

        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: mode == .listen ? .listenOnly : .defaultTap,
            eventsOfInterest: mask,
            callback: spikeTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            SpikeLog.write("tap: CGEvent.tapCreate FAILED for mode '\(mode.rawValue)'")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        self.port = port
        self.source = source
        self.mode = mode
        let enabled = CGEvent.tapIsEnabled(tap: port)
        SpikeLog.write(
            "tap: installed mode='\(mode.rawValue)' options=\(mode == .listen ? "listenOnly" : "defaultTap") "
                + "mask=0x\(String(mask, radix: 16)) enabled=\(enabled)")
        return true
    }

    func remove() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(port)
        self.port = nil
        self.source = nil
        self.mode = nil
        consumedKeys.removeAll()
        SpikeLog.write("tap: removed")
    }

    func reenable() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: true)
    }

    // MARK: - Callback

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passThrough = Unmanaged.passUnretained(event)

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            reenable()
            let reason = type == .tapDisabledByTimeout ? "timeout" : "user input"
            SpikeLog.write("tap: disabled by \(reason); re-enabled")
            return passThrough
        }

        if type == .keyDown || type == .keyUp {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            guard keyCode == 144 || keyCode == 145 else { return passThrough }
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            let flags = event.flags
            let name = type == .keyDown ? "keyDown" : "keyUp"
            SpikeLog.write(
                "event: plain \(name) type=\(type.rawValue) keyCode=\(keyCode) "
                    + "repeat=\(isRepeat) flags=\(Self.describe(flags))")
            return passThrough
        }

        guard type.rawValue == Self.systemDefinedType, let nsEvent = NSEvent(cgEvent: event) else {
            return passThrough
        }

        let subtype = Int(nsEvent.subtype.rawValue)
        let data1 = nsEvent.data1
        let flags = event.flags

        guard subtype == Self.auxControlButtonsSubtype else {
            let data2 = nsEvent.data2
            SpikeLog.write(
                "event: sysdefined type=14 subtype=\(subtype) data1=0x\(String(data1, radix: 16)) "
                    + "data2=0x\(String(data2, radix: 16)) flags=\(Self.describe(flags))")
            return passThrough
        }

        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let keyFlags = data1 & 0x0000_FFFF
        let keyState = (keyFlags & 0xFF00) >> 8
        let isDown = keyState == 0x0A
        let isRepeat = (keyFlags & 0x1) == 1
        let currentMode = mode

        SpikeLog.write(
            "event: sysdefined type=14 subtype=8 data1=0x\(String(data1, radix: 16)) "
                + "keyCode=\(keyCode) (\(Self.keyNames[keyCode] ?? "?")) "
                + "state=0x\(String(keyState, radix: 16)) \(isDown ? "down" : "up") "
                + "repeat=\(isRepeat) flags=\(Self.describe(flags)) "
                + "tap=\(currentMode?.rawValue ?? "none")")

        guard currentMode == .consume else { return passThrough }

        if isDown {
            // Fail open: only swallow the key when we actually applied the change.
            guard apply(keyCode: keyCode) else { return passThrough }
            consumedKeys.insert(keyCode)
            return nil
        }
        return consumedKeys.remove(keyCode) != nil ? nil : passThrough
    }

    // MARK: - Applying keys (consume mode)

    /// Returns true when the key was handled and should be consumed.
    private func apply(keyCode: Int) -> Bool {
        switch keyCode {
        case 0: return stepVolume(direction: 1)
        case 1: return stepVolume(direction: -1)
        case 7: return toggleMute()
        case 2: return stepBrightness(direction: 1)
        case 3: return stepBrightness(direction: -1)
        default: return false
        }
    }

    private func stepVolume(direction: Int) -> Bool {
        guard let device = SpikeAudio.defaultOutputDevice(),
              let old = SpikeAudio.volume(of: device)
        else {
            SpikeLog.write("volume: no default output device or unreadable level; passing through")
            return false
        }
        let target = SpikeStep.stepped(old, direction: direction)
        let ok = SpikeAudio.setVolume(target, on: device)
        let readBack = SpikeAudio.volume(of: device)
        let muted = SpikeAudio.isMuted(device)
        SpikeLog.write(
            "volume: device=\(device) old=\(old) target=\(target) set=\(ok ? "ok" : "FAILED") "
                + "readBack=\(Self.describe(readBack)) muted=\(Self.describe(muted))")
        return ok
    }

    private func toggleMute() -> Bool {
        guard let device = SpikeAudio.defaultOutputDevice(),
              let old = SpikeAudio.isMuted(device)
        else {
            SpikeLog.write("mute: no default output device or unreadable mute; passing through")
            return false
        }
        let ok = SpikeAudio.setMuted(!old, on: device)
        let readBack = SpikeAudio.isMuted(device)
        SpikeLog.write(
            "mute: device=\(device) old=\(old) target=\(!old) set=\(ok ? "ok" : "FAILED") "
                + "readBack=\(Self.describe(readBack))")
        return ok
    }

    private func stepBrightness(direction: Int) -> Bool {
        let display = SpikeDisplay.targetDisplay()
        let canChange = DisplayServicesBridge.canChangeBrightness(display)
        var old: Float = 0
        guard canChange == true, DisplayServicesBridge.getBrightness(display, into: &old) == 0 else {
            SpikeLog.write(
                "brightness: display=\(display) canChange=\(Self.describe(canChange)) "
                    + "not readable; passing through")
            return false
        }
        let target = SpikeStep.stepped(old, direction: direction)
        let status = DisplayServicesBridge.setBrightness(display, to: target)
        let notified = status == 0 && DisplayServicesBridge.notifyBrightnessChanged(display, to: target)
        var readBack: Float = -1
        let readStatus = DisplayServicesBridge.getBrightness(display, into: &readBack)
        SpikeLog.write(
            "brightness: display=\(display) old=\(old) target=\(target) "
                + "setStatus=\(Self.describe(status)) notifiedChanged=\(notified) "
                + "readBack=\(readBack) readStatus=\(Self.describe(readStatus))")
        return status == 0
    }

    // MARK: - Formatting

    private static func describe<T>(_ value: T?) -> String {
        value.map { "\($0)" } ?? "nil"
    }

    private static func describe(_ flags: CGEventFlags) -> String {
        var names: [String] = []
        if flags.contains(.maskShift) { names.append("shift") }
        if flags.contains(.maskControl) { names.append("control") }
        if flags.contains(.maskAlternate) { names.append("option") }
        if flags.contains(.maskCommand) { names.append("command") }
        if flags.contains(.maskSecondaryFn) { names.append("fn") }
        if flags.contains(.maskAlphaShift) { names.append("capsLock") }
        return "0x\(String(flags.rawValue, radix: 16))[\(names.joined(separator: ","))]"
    }
}

private let spikeTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<SpikeEventTap>.fromOpaque(userInfo).takeUnretainedValue()
    return tap.handle(type: type, event: event)
}
#endif
