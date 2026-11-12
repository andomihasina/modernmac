import SwiftUI

/// How long the panel itself fades. The panel's alpha carries the opacity
/// part of a style's appear and disappear, because fading the whole window
/// is the one way a behind-window blur fades cleanly.
struct HUDMotion: Equatable, Sendable {
    var appearFade: TimeInterval
    var disappearFade: TimeInterval
}

/// What the panel needs to know about a style: the outline to place, hit
/// test and fade.
struct HUDStyleGeometry {
    var size: CGSize
    var shape: HUDShape
    var motion: HUDMotion

    var cornerRadius: CGFloat { shape.cornerRadius(forHeight: size.height) }
}

extension HUDStyle {
    /// `notch` (Phase 3) and `circular` (Phase 4) draw as `tahoe` until
    /// their views exist.
    @MainActor
    func geometry(options: HUDOptions) -> HUDStyleGeometry {
        switch self {
        case .tahoe, .notch, .circular:
            return HUDStyleGeometry(
                size: TahoeHUDView.shapeSize(options: options),
                shape: TahoeHUDView.shape(options: options),
                motion: TahoeHUDView.motion)
        }
    }
}

/// The panel's content: the selected style, centred in the panel's canvas.
struct HUDRootView: View {
    let model: HUDViewModel

    var body: some View {
        Group {
            switch model.options.style {
            case .tahoe, .notch, .circular:
                TahoeHUDView(model: model)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }
}
