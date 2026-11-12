import AppKit

/// The stock volume click, played from the system's own file.
@MainActor
final class FeedbackSound: FeedbackSoundPlaying {
    /// Location on macOS 15 (FINDINGS V4).
    static let path =
        "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff"

    private let sound: NSSound?

    init() {
        sound = NSSound(contentsOfFile: Self.path, byReference: true)
        if sound == nil {
            Log.audio.notice("Feedback sound not found; volume steps will be silent")
        }
    }

    /// Plays on the next run loop turn so the event tap callback never waits
    /// for it. A click that is still sounding is cut off and restarted, which
    /// gives one click per step at key-repeat speed.
    func play() {
        guard let sound else { return }
        DispatchQueue.main.async {
            if sound.isPlaying { sound.stop() }
            sound.play()
        }
    }
}

/// System Settings → Sound → "Play feedback when volume is changed".
enum SystemFeedbackPreference {
    private static let key = "com.apple.sound.beep.feedback" as CFString

    /// The stored value, or nil when the key does not exist.
    static var storedValue: Bool? {
        let value = CFPreferencesCopyValue(
            key, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return (value as? NSNumber)?.boolValue
    }

    /// A missing key counts as on: until the setting is first toggled, macOS
    /// stores nothing, shows the setting on and plays the click (FINDINGS V4).
    static var isEnabled: Bool {
        storedValue ?? true
    }
}
