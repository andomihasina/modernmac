#if DEBUG
import AppKit

/// A parsed `modernmac://simulate?…` URL (SPEC §7).
///
/// `kind=volume|brightness`, `level=0…1`, `muted=0|1`,
/// `style=tahoe|notch|circular`, `hold=<seconds>`, plus, until the Settings
/// window exists, `position=topRight|topLeft|topCenter|bottomCenter`,
/// `percent=0|1`, `name=0|1` and `interactive=0|1`. `pill=1` treats the
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

/// Receives `modernmac://simulate` URLs and drives the coordinator exactly
/// as a key press would, without touching hardware.
@MainActor
final class SimulateURLHandler: NSObject {
    private let onRequest: (SimulateRequest) -> Void

    init(onRequest: @escaping (SimulateRequest) -> Void) {
        self.onRequest = onRequest
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
              let url = URL(string: text),
              let request = SimulateRequest(url: url)
        else {
            Log.app.error("Unreadable simulate URL")
            return
        }
        Log.trace { "simulate \(text)" }
        onRequest(request)
    }
}
#endif
