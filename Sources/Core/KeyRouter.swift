import Foundation

/// What ModernMac does for a key it takes over.
enum KeyAction: Equatable, Sendable {
    /// `invertFeedback` flips the feedback-sound preference for this press (⇧ held).
    case volumeStep(StepDirection, StepSize, invertFeedback: Bool)
    case toggleMute
    case brightnessStep(StepDirection, StepSize)
}

enum KeyDecision: Equatable, Sendable {
    /// Leave the event alone; macOS handles it and shows its own HUD.
    case passThrough
    /// Swallow the event and perform the action ourselves.
    case consume(KeyAction)
}

/// The feature toggles that can switch takeover off.
struct RoutingOptions: Equatable, Sendable {
    var isEnabled = true
    var handleVolume = true
    var handleBrightness = true
}

/// The routing table from SPEC §4.2 as pure logic.
///
/// Anything not listed there passes through. That includes every combination
/// with ⌃ or ⌘, where macOS has its own meanings (external display brightness,
/// display mirroring), so ModernMac never hides a system shortcut.
enum KeyRouter {
    static func route(
        key: MediaKey, modifiers: KeyModifiers, options: RoutingOptions = RoutingOptions()
    ) -> KeyDecision {
        guard options.isEnabled else { return .passThrough }

        switch key {
        case .soundUp, .soundDown:
            guard options.handleVolume else { return .passThrough }
            let direction: StepDirection = key == .soundUp ? .up : .down
            switch modifiers {
            case []:
                return .consume(.volumeStep(direction, .normal, invertFeedback: false))
            case [.shift]:
                return .consume(.volumeStep(direction, .normal, invertFeedback: true))
            case [.shift, .option]:
                return .consume(.volumeStep(direction, .fine, invertFeedback: false))
            default:
                // ⌥ alone opens Sound settings.
                return .passThrough
            }

        case .mute:
            guard options.handleVolume else { return .passThrough }
            switch modifiers {
            case [], [.shift]:
                return .consume(.toggleMute)
            default:
                // ⌥ alone opens Sound settings.
                return .passThrough
            }

        case .brightnessUp, .brightnessDown:
            guard options.handleBrightness else { return .passThrough }
            let direction: StepDirection = key == .brightnessUp ? .up : .down
            switch modifiers {
            case []:
                return .consume(.brightnessStep(direction, .normal))
            case [.shift, .option]:
                return .consume(.brightnessStep(direction, .fine))
            default:
                // ⌥ alone opens Displays settings; ⌃ adjusts an external display.
                return .passThrough
            }

        case .play, .next, .previous, .fast, .rewind,
             .illuminationUp, .illuminationDown, .illuminationToggle:
            return .passThrough
        }
    }
}
