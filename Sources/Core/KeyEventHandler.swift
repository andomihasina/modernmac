import Foundation

/// Turns a decoded media key into a hardware change and a HUD update, and
/// answers the one question the event tap asks: consume this event or not.
///
/// Fail open: the answer is "consume" only when the change was actually
/// applied. A feature that is switched off, a device without settable volume,
/// a display that cannot be adjusted or a failing system call all leave the
/// event untouched, so macOS handles the key as if ModernMac were not running.
@MainActor
final class KeyEventHandler {
    private let volume: any VolumeControlling
    private let brightness: any BrightnessControlling
    private let feedback: any FeedbackSoundPlaying
    private let options: () -> RoutingOptions
    private let isFeedbackEnabled: () -> Bool
    private let present: (HUDState, _ displayID: UInt32?) -> Void

    /// Per-event detail for debug builds. The message is only built when set.
    var trace: ((() -> String) -> Void)?

    /// Keys whose key-down we consumed. Their key-up is consumed too, so the
    /// system never sees half a press.
    private var consumedKeys: Set<MediaKey> = []

    /// - Parameters:
    ///   - options: Read on every key-down, so toggles apply at once.
    ///   - isFeedbackEnabled: The feedback-sound preference before ⇧ inverts it.
    ///   - present: Receives the new state, plus the display for brightness.
    init(
        volume: any VolumeControlling,
        brightness: any BrightnessControlling,
        feedback: any FeedbackSoundPlaying,
        options: @escaping () -> RoutingOptions,
        isFeedbackEnabled: @escaping () -> Bool,
        present: @escaping (HUDState, _ displayID: UInt32?) -> Void
    ) {
        self.volume = volume
        self.brightness = brightness
        self.feedback = feedback
        self.options = options
        self.isFeedbackEnabled = isFeedbackEnabled
        self.present = present
    }

    /// Returns true when the event must be consumed.
    func handle(_ event: MediaKeyEvent) -> Bool {
        guard event.isDown else {
            return consumedKeys.remove(event.key) != nil
        }

        let decision = KeyRouter.route(
            key: event.key, modifiers: event.modifiers, options: options())
        guard case .consume(let action) = decision else {
            // A stale entry (key-up lost while the tap was off) must not
            // swallow the key-up of a press we are letting through.
            consumedKeys.remove(event.key)
            trace?({ "\(event.key) \(event.modifiers.rawValue) -> pass through (routing)" })
            return false
        }

        do {
            try perform(action)
        } catch {
            consumedKeys.remove(event.key)
            trace?({ "\(event.key) -> pass through (\(action) failed: \(error))" })
            return false
        }
        consumedKeys.insert(event.key)
        return true
    }

    /// Forget half-finished presses. Call when the tap goes away.
    func reset() {
        consumedKeys.removeAll()
    }

    // MARK: - Actions

    private func perform(_ action: KeyAction) throws {
        switch action {
        case .volumeStep(let direction, let size, let invertFeedback):
            try stepVolume(direction, size, invertFeedback: invertFeedback)
        case .toggleMute:
            try toggleMute()
        case .brightnessStep(let direction, let size):
            try stepBrightness(direction, size)
        }
    }

    private func stepVolume(
        _ direction: StepDirection, _ size: StepSize, invertFeedback: Bool
    ) throws {
        var reading = try volume.read()
        let old = reading.level
        let target = StepMath.step(old, direction, size)
        try volume.setLevel(target)
        reading.level = target

        // Stock macOS unmutes on volume up and on volume down (FINDINGS V9).
        // The level is already set, so the key counts as handled even if the
        // unmute fails; the HUD then keeps showing the muted state.
        if reading.isMuted, (try? volume.setMuted(false)) != nil {
            reading.isMuted = false
        }

        present(.volume(reading), nil)
        let playsFeedback = isFeedbackEnabled() != invertFeedback
        if playsFeedback { feedback.play() }
        trace?({
            "volume \(old) -> \(target) muted=\(reading.isMuted) feedback=\(playsFeedback)"
        })
    }

    private func toggleMute() throws {
        var reading = try volume.read()
        try volume.setMuted(!reading.isMuted)
        reading.isMuted.toggle()
        present(.volume(reading), nil)
        trace?({ "mute -> \(reading.isMuted) level=\(reading.level)" })
    }

    private func stepBrightness(_ direction: StepDirection, _ size: StepSize) throws {
        guard brightness.isAvailable else { throw HardwareError.unavailable }
        var reading = try brightness.read()
        let old = reading.level
        let target = StepMath.step(old, direction, size)
        try brightness.setLevel(target, displayID: reading.displayID)
        reading.level = target
        present(.brightness(reading), reading.displayID)
        trace?({ "brightness \(old) -> \(target) display=\(reading.displayID)" })
    }
}
