import Foundation
import Observation

/// What the style views draw from. `HUDPresenter` writes it; the snapshot
/// renderer fills one in by hand.
@MainActor
@Observable
final class HUDViewModel {
    enum Phase: Equatable {
        /// Off screen, ready to appear.
        case idle
        case shown
        /// Fading out.
        case leaving
    }

    var state: HUDState
    var options: HUDOptions
    var phase = Phase.idle
    /// The pointer is over the shape (interactive only).
    var isHovering = false
    var isDragging = false
    /// False for the first frame of an appearance and while dragging, so the
    /// bar starts at the right level instead of sliding there.
    var animatesLevel = false
    /// Size of the physical notch on the screen the HUD is on; nil when
    /// that screen has none.
    var notchSize: CGSize?

    /// Drag on the level bar: began / moved to a level.
    @ObservationIgnored var onDragChanged: ((Double) -> Void)?
    @ObservationIgnored var onDragEnded: (() -> Void)?

    init(state: HUDState, options: HUDOptions = HUDOptions()) {
        self.state = state
        self.options = options
    }

    /// The level the bar and the percentage show: muted reads as empty.
    var displayedLevel: Double {
        state.isMuted ? 0 : min(max(state.level, 0), 1)
    }

    var percentageText: String {
        "\(Int((displayedLevel * 100).rounded()))%"
    }

    /// The label for "Show device name".
    var deviceLabel: String {
        if let name = state.deviceName, !name.isEmpty { return name }
        return state.kind == .volume ? "Sound" : "Display"
    }
}
