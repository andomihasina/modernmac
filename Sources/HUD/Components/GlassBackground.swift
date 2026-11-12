import AppKit
import SwiftUI

// MARK: - Environment

/// How glass is drawn.
enum HUDRenderMode: Sendable {
    /// In the real panel: a behind-window blur.
    case live
    /// Offscreen (snapshots, Settings preview): a flat translucent tint,
    /// because offscreen rendering cannot capture a behind-window blur.
    case snapshot
}

private struct HUDRenderModeKey: EnvironmentKey {
    static let defaultValue = HUDRenderMode.live
}

private struct HUDIncreaseContrastKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

private struct HUDReduceMotionKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    var hudRenderMode: HUDRenderMode {
        get { self[HUDRenderModeKey.self] }
        set { self[HUDRenderModeKey.self] = newValue }
    }

    /// Overrides the system's Increase Contrast setting (snapshots). `nil` follows the system.
    var hudIncreaseContrast: Bool? {
        get { self[HUDIncreaseContrastKey.self] }
        set { self[HUDIncreaseContrastKey.self] = newValue }
    }

    /// Overrides the system's Reduce Motion setting. `nil` follows the system.
    var hudReduceMotion: Bool? {
        get { self[HUDReduceMotionKey.self] }
        set { self[HUDReduceMotionKey.self] = newValue }
    }
}

// MARK: - Shape

/// The outline of a HUD: a capsule or a continuous rounded rectangle.
enum HUDShape: InsettableShape, Equatable {
    case capsule
    case rounded(CGFloat)

    nonisolated func path(in rect: CGRect) -> Path {
        switch self {
        case .capsule:
            return Capsule(style: .continuous).path(in: rect)
        case .rounded(let radius):
            return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
        }
    }

    nonisolated func inset(by amount: CGFloat) -> some InsettableShape {
        InsetHUDShape(shape: self, amount: amount)
    }

    /// Corner radius for hit testing a shape of the given height.
    func cornerRadius(forHeight height: CGFloat) -> CGFloat {
        switch self {
        case .capsule: return height / 2
        case .rounded(let radius): return radius
        }
    }
}

struct InsetHUDShape: InsettableShape {
    var shape: HUDShape
    var amount: CGFloat

    nonisolated func path(in rect: CGRect) -> Path {
        let inner = rect.insetBy(dx: amount, dy: amount)
        switch shape {
        case .capsule:
            return HUDShape.capsule.path(in: inner)
        case .rounded(let radius):
            return HUDShape.rounded(max(0, radius - amount)).path(in: inner)
        }
    }

    nonisolated func inset(by amount: CGFloat) -> InsetHUDShape {
        InsetHUDShape(shape: shape, amount: self.amount + amount)
    }
}

/// Everything around a shape, out to `reach`: masks the shadow so it never
/// darkens the glass itself.
private struct OutsideShape: Shape {
    var shape: HUDShape
    var reach: CGFloat

    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect.insetBy(dx: -reach, dy: -reach))
        path.addPath(shape.path(in: rect))
        return path
    }
}

// MARK: - Glass

/// The HUD's material: blur, a rim that catches light from above, and a
/// soft shadow (SPEC §5.3).
struct GlassBackground: View {
    // Rim: 1 pt, lit from the top.
    static let rimWidth: CGFloat = 1
    static let rimTopOpacity = 0.35
    static let rimBottomOpacity = 0.06
    // Hairline just inside the edge that separates the glass from a
    // background of similar brightness.
    static let edgeWidth: CGFloat = 0.5
    static let edgeOpacityDark = 0.30
    static let edgeOpacityLight = 0.10
    // Shadow.
    static let shadowRadius: CGFloat = 18
    static let shadowYOffset: CGFloat = 6
    static let shadowOpacity = 0.18
    // Sheen over the material, top to bottom.
    static let sheenTopOpacity = 0.10
    // Stand-in for the blur in `.snapshot` mode (white level, opacity).
    static let snapshotTintDark = (white: 0.13, opacity: 0.78)
    static let snapshotTintLight = (white: 0.96, opacity: 0.78)
    // Increase Contrast: opaque fill, strong rim.
    static let contrastFillDark = 0.11
    static let contrastFillLight = 0.97
    static let contrastRimWidth: CGFloat = 1.5
    static let contrastRimOpacity = 0.75

    var shape: HUDShape

    @Environment(\.hudRenderMode) private var renderMode
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var systemContrast
    @Environment(\.hudIncreaseContrast) private var contrastOverride

    private var increasesContrast: Bool {
        contrastOverride ?? (systemContrast == .increased)
    }

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        ZStack {
            shadow
            fill
            if increasesContrast {
                shape.strokeBorder(
                    Color.primary.opacity(Self.contrastRimOpacity), lineWidth: Self.contrastRimWidth)
            } else {
                sheen
                edge
                rim
            }
        }
    }

    private var shadow: some View {
        shape
            .fill(Color.black)
            .shadow(
                color: .black.opacity(Self.shadowOpacity),
                radius: Self.shadowRadius, y: Self.shadowYOffset)
            .mask {
                OutsideShape(shape: shape, reach: Self.shadowRadius * 3)
                    .fill(style: FillStyle(eoFill: true))
            }
    }

    @ViewBuilder
    private var fill: some View {
        if increasesContrast {
            shape.fill(Color(white: isDark ? Self.contrastFillDark : Self.contrastFillLight))
        } else {
            switch renderMode {
            case .live:
                VisualEffectBackdrop(shape: shape)
            case .snapshot:
                let tint = isDark ? Self.snapshotTintDark : Self.snapshotTintLight
                shape.fill(Color(white: tint.white, opacity: tint.opacity))
            }
        }
    }

    private var sheen: some View {
        shape.fill(
            LinearGradient(
                colors: [.white.opacity(Self.sheenTopOpacity), .white.opacity(0)],
                startPoint: .top, endPoint: .center))
    }

    private var edge: some View {
        shape.strokeBorder(
            Color.black.opacity(isDark ? Self.edgeOpacityDark : Self.edgeOpacityLight),
            lineWidth: Self.edgeWidth)
    }

    private var rim: some View {
        shape
            .inset(by: Self.edgeWidth)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        .white.opacity(Self.rimTopOpacity),
                        .white.opacity(Self.rimBottomOpacity),
                    ],
                    startPoint: .top, endPoint: .bottom),
                lineWidth: Self.rimWidth)
    }
}

// MARK: - Behind-window blur

/// `NSVisualEffectView` clipped to the shape with a mask image, the variant
/// that looked right in the Phase 0 spike (FINDINGS V5, capsule A).
private struct VisualEffectBackdrop: NSViewRepresentable {
    var shape: HUDShape

    func makeNSView(context: Context) -> ShapedVisualEffectView {
        let view = ShapedVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        // The panel is never key; without this the material would go flat.
        view.state = .active
        view.shape = shape
        return view
    }

    func updateNSView(_ view: ShapedVisualEffectView, context: Context) {
        view.shape = shape
    }
}

private final class ShapedVisualEffectView: NSVisualEffectView {
    var shape = HUDShape.capsule {
        didSet {
            if shape != oldValue { rebuildMask() }
        }
    }

    private var maskedSize = CGSize.zero

    override func layout() {
        super.layout()
        if bounds.size != maskedSize { rebuildMask() }
    }

    private func rebuildMask() {
        let size = bounds.size
        maskedSize = size
        guard size.width > 0, size.height > 0 else {
            maskImage = nil
            return
        }
        let path = shape.path(in: CGRect(origin: .zero, size: size)).cgPath
        maskImage = NSImage(size: size, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(path)
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
            return true
        }
    }
}
