import SwiftUI

/// How the panel itself behaves around an appearance. The panel's alpha
/// carries the opacity part of a style's appear and disappear, because
/// fading the whole window is the one way a behind-window blur fades cleanly.
struct HUDMotion: Equatable, Sendable {
    /// Fade-in of the panel; 0 shows it at once.
    var appearFade: TimeInterval
    /// Fade-out of the panel; 0 keeps it opaque until it is ordered out.
    var disappearFade: TimeInterval
    /// From the start of a hide until the panel is ordered out.
    var orderOutDelay: TimeInterval
}

/// Where a style goes on a screen, in screen coordinates.
struct HUDPlacement: Equatable {
    var panelFrame: CGRect
    /// The visible shape: where the pointer counts as on the HUD.
    var hitFrame: CGRect
    /// The same while the pointer is on the HUD (a style may grow on hover).
    var hoverHitFrame: CGRect
    var hitCornerRadius: CGFloat
    /// Drawn over the menu bar (the level proven in FINDINGS V6).
    var isOverMenuBar: Bool
    var motion: HUDMotion
}

extension HUDStyle {
    /// `circular` (Phase 4) draws as `tahoe` until its view exists.
    @MainActor
    func placement(options: HUDOptions, screen: ScreenMetrics, reduceMotion: Bool) -> HUDPlacement {
        switch self {
        case .tahoe, .circular:
            return TahoeHUDView.placement(options: options, screen: screen)
        case .notch:
            return NotchHUDView.placement(
                options: options, screen: screen, reduceMotion: reduceMotion)
        }
    }
}

/// The panel's content: the selected style. Each style places itself in
/// the panel's canvas.
struct HUDRootView: View {
    let model: HUDViewModel

    var body: some View {
        Group {
            switch model.options.style {
            case .tahoe, .circular:
                TahoeHUDView(model: model)
            case .notch:
                NotchHUDView(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}
