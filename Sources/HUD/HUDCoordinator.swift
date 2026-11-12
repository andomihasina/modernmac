import Foundation

/// A pending timer that can be called off.
@MainActor
protocol HUDCancellable: AnyObject {
    func cancel()
}

/// The coordinator's clock. Injected so tests run without waiting.
@MainActor
protocol HUDScheduling: AnyObject {
    func schedule(
        after delay: TimeInterval, _ action: @escaping @MainActor () -> Void
    ) -> any HUDCancellable
}

/// What the HUD should look like right now.
struct HUDPresentation: Equatable, Sendable {
    var isVisible = false
    /// Kept after hiding so a style can fade out with its last content.
    var state: HUDState?
    /// The display to show on, when the event belongs to one (brightness).
    var displayID: UInt32?
}

/// Decides when the HUD is up: `hidden → visible → hidden`, with `visible`
/// held open while the pointer hovers the HUD or a drag is in progress.
@MainActor
final class HUDCoordinator {
    nonisolated static let defaultHideDelay: TimeInterval = 1.5
    /// How long the HUD stays after a drag is released outside it.
    nonisolated static let dragReleaseDelay: TimeInterval = 0.8

    private let scheduler: any HUDScheduling
    private let hideDelay: () -> TimeInterval
    private var hideTimer: (any HUDCancellable)?

    private(set) var isHovering = false
    private(set) var isDragging = false

    private(set) var presentation = HUDPresentation() {
        didSet {
            if presentation != oldValue { onChange?(presentation) }
        }
    }

    /// Called whenever `presentation` changes.
    var onChange: ((HUDPresentation) -> Void)?

    init(
        scheduler: any HUDScheduling,
        hideDelay: @escaping () -> TimeInterval = { HUDCoordinator.defaultHideDelay }
    ) {
        self.scheduler = scheduler
        self.hideDelay = hideDelay
    }

    /// A key was handled: show the state and restart the hide timer. A
    /// different kind arriving while visible replaces the content in place.
    func show(_ state: HUDState, displayID: UInt32? = nil) {
        presentation = HUDPresentation(isVisible: true, state: state, displayID: displayID)
        restartHideTimer(after: hideDelay())
    }

    /// Something else changed the level. Refreshes a visible HUD of the same
    /// kind; never opens one and never extends its time on screen.
    func update(_ state: HUDState) {
        guard presentation.isVisible, presentation.state?.kind == state.kind else { return }
        presentation.state = state
    }

    func setHovering(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        isHovering = hovering
        guard presentation.isVisible else { return }
        if hovering {
            cancelHideTimer()
        } else {
            restartHideTimer(after: hideDelay())
        }
    }

    func beginDrag() {
        isDragging = true
        cancelHideTimer()
    }

    func endDrag() {
        guard isDragging else { return }
        isDragging = false
        guard presentation.isVisible else { return }
        restartHideTimer(after: Self.dragReleaseDelay)
    }

    func hide() {
        cancelHideTimer()
        // A hidden panel gets no mouse-exit or mouse-up, so clear the holds.
        isHovering = false
        isDragging = false
        presentation.isVisible = false
    }

    private func restartHideTimer(after delay: TimeInterval) {
        cancelHideTimer()
        guard !isHovering, !isDragging else { return }
        hideTimer = scheduler.schedule(after: delay) { [weak self] in
            self?.hide()
        }
    }

    private func cancelHideTimer() {
        hideTimer?.cancel()
        hideTimer = nil
    }
}

/// The real clock: a timer on the main run loop, in common modes so it also
/// fires while a menu is open or a control is tracking.
@MainActor
final class MainRunLoopScheduler: HUDScheduling {
    private final class TimerToken: HUDCancellable {
        let timer: Timer
        init(timer: Timer) { self.timer = timer }
        func cancel() { timer.invalidate() }
    }

    func schedule(
        after delay: TimeInterval, _ action: @escaping @MainActor () -> Void
    ) -> any HUDCancellable {
        let timer = Timer(timeInterval: delay, repeats: false) { _ in
            MainActor.assumeIsolated(action)
        }
        RunLoop.main.add(timer, forMode: .common)
        return TimerToken(timer: timer)
    }
}
