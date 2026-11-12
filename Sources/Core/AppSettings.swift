import Foundation
import Observation

/// User settings, stored in `UserDefaults`. Only the keys the engine needs
/// exist so far; the rest of SPEC §6 arrives with the features that use them.
@MainActor
@Observable
final class AppSettings {
    enum FeedbackSoundPolicy: String, Sendable {
        case followSystem
        case always
        case never
    }

    static let hideDelayRange: ClosedRange<Double> = 0.8...3.0
    static let defaultHideDelay = 1.5

    private enum Key {
        static let isEnabled = "isEnabled"
        static let handleVolume = "handleVolume"
        static let handleBrightness = "handleBrightness"
        static let hideDelay = "hideDelay"
        static let playFeedbackSound = "playFeedbackSound"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var isEnabled: Bool { didSet { defaults.set(isEnabled, forKey: Key.isEnabled) } }
    var handleVolume: Bool { didSet { defaults.set(handleVolume, forKey: Key.handleVolume) } }
    var handleBrightness: Bool {
        didSet { defaults.set(handleBrightness, forKey: Key.handleBrightness) }
    }
    /// Seconds the HUD stays up after the last key. Read through `clampedHideDelay`.
    var hideDelay: Double { didSet { defaults.set(hideDelay, forKey: Key.hideDelay) } }
    var playFeedbackSound: FeedbackSoundPolicy {
        didSet { defaults.set(playFeedbackSound.rawValue, forKey: Key.playFeedbackSound) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Key.isEnabled) as? Bool ?? true
        handleVolume = defaults.object(forKey: Key.handleVolume) as? Bool ?? true
        handleBrightness = defaults.object(forKey: Key.handleBrightness) as? Bool ?? true
        hideDelay = defaults.object(forKey: Key.hideDelay) as? Double ?? Self.defaultHideDelay
        playFeedbackSound = defaults.string(forKey: Key.playFeedbackSound)
            .flatMap(FeedbackSoundPolicy.init(rawValue:)) ?? .followSystem
    }

    var routingOptions: RoutingOptions {
        RoutingOptions(
            isEnabled: isEnabled, handleVolume: handleVolume, handleBrightness: handleBrightness)
    }

    var clampedHideDelay: Double {
        min(max(hideDelay, Self.hideDelayRange.lowerBound), Self.hideDelayRange.upperBound)
    }

    /// Whether a volume step should click, before ⇧ inverts it.
    func isFeedbackSoundEnabled(systemSetting: Bool) -> Bool {
        switch playFeedbackSound {
        case .followSystem: return systemSetting
        case .always: return true
        case .never: return false
        }
    }
}
