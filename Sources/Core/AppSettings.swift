import Foundation
import Observation

enum HUDStyle: String, CaseIterable, Sendable {
    case tahoe
    case notch
    case circular
}

/// The settings a HUD style draws from, as one value.
struct HUDOptions: Equatable, Sendable {
    var style = HUDStyle.tahoe
    var position = HUDPosition.topRight
    var isInteractive = true
    var showsPercentage = false
    var showsDeviceName = false
}

/// User settings, stored in `UserDefaults` under the keys of SPEC §6. Every
/// change is written at once and read by the engine at its next use, so
/// nothing needs a relaunch.
@MainActor
@Observable
final class AppSettings {
    enum FeedbackSoundPolicy: String, CaseIterable, Sendable {
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
        static let style = "style"
        static let position = "position"
        static let isInteractive = "isInteractive"
        static let showPercentage = "showPercentage"
        static let showDeviceName = "showDeviceName"
        static let showMenuBarIcon = "showMenuBarIcon"
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
    var style: HUDStyle { didSet { defaults.set(style.rawValue, forKey: Key.style) } }
    var position: HUDPosition { didSet { defaults.set(position.rawValue, forKey: Key.position) } }
    /// Whether the HUD reacts to the pointer (hover, drag).
    var isInteractive: Bool { didSet { defaults.set(isInteractive, forKey: Key.isInteractive) } }
    var showPercentage: Bool { didSet { defaults.set(showPercentage, forKey: Key.showPercentage) } }
    var showDeviceName: Bool { didSet { defaults.set(showDeviceName, forKey: Key.showDeviceName) } }
    /// The menu bar extra. Dragging the icon off the menu bar turns this off
    /// too; opening the app again shows Settings, so there is a way back.
    var showMenuBarIcon: Bool {
        didSet { defaults.set(showMenuBarIcon, forKey: Key.showMenuBarIcon) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Key.isEnabled) as? Bool ?? true
        handleVolume = defaults.object(forKey: Key.handleVolume) as? Bool ?? true
        handleBrightness = defaults.object(forKey: Key.handleBrightness) as? Bool ?? true
        hideDelay = defaults.object(forKey: Key.hideDelay) as? Double ?? Self.defaultHideDelay
        playFeedbackSound = defaults.string(forKey: Key.playFeedbackSound)
            .flatMap(FeedbackSoundPolicy.init(rawValue:)) ?? .followSystem
        style = defaults.string(forKey: Key.style).flatMap(HUDStyle.init(rawValue:)) ?? .tahoe
        position = defaults.string(forKey: Key.position)
            .flatMap(HUDPosition.init(rawValue:)) ?? .topRight
        isInteractive = defaults.object(forKey: Key.isInteractive) as? Bool ?? true
        showPercentage = defaults.object(forKey: Key.showPercentage) as? Bool ?? false
        showDeviceName = defaults.object(forKey: Key.showDeviceName) as? Bool ?? false
        showMenuBarIcon = defaults.object(forKey: Key.showMenuBarIcon) as? Bool ?? true
    }

    var hudOptions: HUDOptions {
        HUDOptions(
            style: style,
            position: position,
            isInteractive: isInteractive,
            showsPercentage: showPercentage,
            showsDeviceName: showDeviceName)
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
