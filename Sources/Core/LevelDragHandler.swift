import Foundation

/// Applies a drag on the HUD's level bar to the hardware (SPEC §5.5).
///
/// The HUD follows the pointer on every change; hardware writes are limited
/// to one per `minimumWriteInterval`, always ending on the newest level.
@MainActor
final class LevelDragHandler {
    nonisolated static let minimumWriteInterval: TimeInterval = 0.016

    private enum Target {
        case volume(VolumeReading)
        case brightness(BrightnessReading)
    }

    private let volume: any VolumeControlling
    private let brightness: any BrightnessControlling
    private let feedback: any FeedbackSoundPlaying
    private let isFeedbackEnabled: () -> Bool
    private let scheduler: any HUDScheduling
    private let present: (HUDState) -> Void

    private var target: Target?
    private var needsUnmute = false
    private var pendingLevel: Double?
    private var lastWriteTime: TimeInterval = -.infinity
    private var flushTimer: (any HUDCancellable)?

    /// Per-event detail for debug builds.
    var trace: ((() -> String) -> Void)?

    /// True between `begin` and `end`. Level changes reported by the
    /// hardware should not be shown meanwhile: the pointer is the truth.
    var isActive: Bool { target != nil }

    /// - Parameters:
    ///   - isFeedbackEnabled: The feedback-sound preference, read on release.
    ///   - present: Receives the state to show while dragging and on release.
    init(
        volume: any VolumeControlling,
        brightness: any BrightnessControlling,
        feedback: any FeedbackSoundPlaying,
        isFeedbackEnabled: @escaping () -> Bool,
        scheduler: any HUDScheduling,
        present: @escaping (HUDState) -> Void
    ) {
        self.volume = volume
        self.brightness = brightness
        self.feedback = feedback
        self.isFeedbackEnabled = isFeedbackEnabled
        self.scheduler = scheduler
        self.present = present
    }

    /// Starts a drag. Returns false when the hardware cannot be adjusted;
    /// the drag is then ignored.
    @discardableResult
    func begin(_ kind: HUDKind) -> Bool {
        if isActive { end() }
        do {
            switch kind {
            case .volume:
                let reading = try volume.read()
                needsUnmute = reading.isMuted
                target = .volume(reading)
            case .brightness:
                guard brightness.isAvailable else { return false }
                needsUnmute = false
                target = .brightness(try brightness.read())
            }
        } catch {
            trace?({ "drag begin \(kind) failed: \(error)" })
            return false
        }
        pendingLevel = nil
        lastWriteTime = -.infinity
        return true
    }

    /// The pointer moved. `level` is 0…1 and is not snapped to the key grid.
    func change(to level: Double) {
        guard let target else { return }
        let level = level.isFinite ? min(max(level, 0), 1) : 0

        switch target {
        case .volume(var reading):
            reading.level = level
            // Like the keys, moving the level unmutes.
            reading.isMuted = false
            self.target = .volume(reading)
            present(.volume(reading))
        case .brightness(var reading):
            reading.level = level
            self.target = .brightness(reading)
            present(.brightness(reading))
        }

        pendingLevel = level
        let wait = Self.minimumWriteInterval - (scheduler.now - lastWriteTime)
        if wait <= 1e-9 {
            writePending()
        } else if flushTimer == nil {
            flushTimer = scheduler.schedule(after: wait) { [weak self] in
                self?.flushTimer = nil
                self?.writePending()
            }
        }
    }

    /// Mouse up: write the final level, click once for volume if the
    /// preference says so, and show what the hardware settled on.
    func end() {
        guard let target else { return }
        let hadChanges = pendingLevel != nil || lastWriteTime > -.infinity
        writePending()
        self.target = nil

        switch target {
        case .volume:
            if hadChanges, isFeedbackEnabled() { feedback.play() }
            if let reading = try? volume.read() { present(.volume(reading)) }
        case .brightness:
            if let reading = try? brightness.read() { present(.brightness(reading)) }
        }
    }

    private func writePending() {
        flushTimer?.cancel()
        flushTimer = nil
        guard let level = pendingLevel, let target else { return }
        pendingLevel = nil
        lastWriteTime = scheduler.now

        do {
            switch target {
            case .volume:
                try volume.setLevel(level)
                if needsUnmute {
                    try volume.setMuted(false)
                    needsUnmute = false
                }
            case .brightness(let reading):
                try brightness.setLevel(level, displayID: reading.displayID)
            }
        } catch {
            // No key to pass through here; the next write tries again.
            trace?({ "drag write \(level) failed: \(error)" })
        }
    }
}
