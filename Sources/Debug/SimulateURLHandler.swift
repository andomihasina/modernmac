#if DEBUG
import AppKit

/// A parsed `modernmac://simulate?…` URL (SPEC §7).
///
/// `kind=volume|brightness`, `level=0…1`, `muted=0|1`,
/// `style=tahoe|notch|circular`, `hold=<seconds>`, plus
/// `position=topRight|topLeft|topCenter|bottomCenter`, `percent=0|1`,
/// `name=0|1` and `interactive=0|1`, which apply to that one HUD only. `pill=1` treats the
/// screen as having no notch, to see the `notch` style's fallback pill on a
/// notched Mac.
struct SimulateRequest: Equatable {
    var kind = HUDKind.volume
    var level = 0.5
    var isMuted = false
    var hold: TimeInterval?
    var style: HUDStyle?
    var position: HUDPosition?
    var showsPercentage: Bool?
    var showsDeviceName: Bool?
    var isInteractive: Bool?
    var forcesPill = false

    /// Nil when the URL is not a simulate URL or a value cannot be read.
    init?(url: URL) {
        guard url.scheme == "modernmac", url.host == "simulate",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }

        for item in components.queryItems ?? [] {
            let value = item.value ?? ""
            switch item.name {
            case "kind":
                switch value {
                case "volume": kind = .volume
                case "brightness": kind = .brightness
                default: return nil
                }
            case "level":
                guard let number = Double(value), number.isFinite else { return nil }
                level = min(max(number, 0), 1)
            case "muted":
                guard let flag = Self.flag(value) else { return nil }
                isMuted = flag
            case "hold":
                guard let seconds = Double(value), seconds.isFinite, seconds > 0 else { return nil }
                hold = seconds
            case "style":
                guard let parsed = HUDStyle(rawValue: value) else { return nil }
                style = parsed
            case "position":
                guard let parsed = HUDPosition(rawValue: value) else { return nil }
                position = parsed
            case "percent":
                guard let flag = Self.flag(value) else { return nil }
                showsPercentage = flag
            case "name":
                guard let flag = Self.flag(value) else { return nil }
                showsDeviceName = flag
            case "interactive":
                guard let flag = Self.flag(value) else { return nil }
                isInteractive = flag
            case "pill":
                guard let flag = Self.flag(value) else { return nil }
                forcesPill = flag
            default:
                return nil
            }
        }
    }

    private static func flag(_ value: String) -> Bool? {
        switch value {
        case "1", "true": return true
        case "0", "false": return false
        default: return nil
        }
    }

    /// The state a key press would have produced.
    var state: HUDState {
        switch kind {
        case .volume:
            return .volume(VolumeReading(
                level: level, isMuted: isMuted, deviceName: "MacBook Air Speakers"))
        case .brightness:
            return .brightness(BrightnessReading(
                level: level, displayID: 0, displayName: "Built-in Display"))
        }
    }

    /// The user's options with this request's overrides on top.
    func options(over base: HUDOptions) -> HUDOptions {
        var options = base
        if let style { options.style = style }
        if let position { options.position = position }
        if let showsPercentage { options.showsPercentage = showsPercentage }
        if let showsDeviceName { options.showsDeviceName = showsDeviceName }
        if let isInteractive { options.isInteractive = isInteractive }
        return options
    }
}

/// The other debug URLs: what a click in the app's own UI would do, so the
/// shell around the HUD can be exercised from the terminal too.
///
/// `modernmac://show?window=settings|onboarding` opens that window.
/// `modernmac://set?showMenuBarIcon=0|1` changes that setting in the
/// running app, as the toggle in Settings does.
enum DebugCommand: Equatable {
    enum Window: String {
        case settings
        case onboarding
    }

    case show(Window)
    case setMenuBarIcon(Bool)

    /// Nil when the URL is not one of these or a value cannot be read.
    init?(url: URL) {
        guard url.scheme == "modernmac",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems, items.count == 1,
              let value = items[0].value
        else { return nil }

        switch (url.host, items[0].name) {
        case ("show", "window"):
            guard let window = Window(rawValue: value) else { return nil }
            self = .show(window)
        case ("set", "showMenuBarIcon"):
            switch value {
            case "1", "true": self = .setMenuBarIcon(true)
            case "0", "false": self = .setMenuBarIcon(false)
            default: return nil
            }
        default:
            return nil
        }
    }
}

/// Receives `modernmac://` URLs. `simulate` drives the coordinator exactly
/// as a key press would, without touching hardware; the rest are
/// `DebugCommand`s.
@MainActor
final class SimulateURLHandler: NSObject {
    private let onRequest: (SimulateRequest) -> Void
    private let onCommand: (DebugCommand) -> Void

    init(
        onRequest: @escaping (SimulateRequest) -> Void,
        onCommand: @escaping (DebugCommand) -> Void
    ) {
        self.onRequest = onRequest
        self.onCommand = onCommand
        super.init()
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handle(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL))
    }

    @objc private func handle(
        _ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor
    ) {
        guard let text = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: text)
        else {
            Log.app.error("Unreadable debug URL")
            return
        }
        if let request = SimulateRequest(url: url) {
            Log.trace { "simulate \(text)" }
            onRequest(request)
        } else if let command = DebugCommand(url: url) {
            Log.trace { "debug \(text)" }
            onCommand(command)
        } else {
            Log.app.error("Unreadable debug URL")
        }
    }
}
#endif
