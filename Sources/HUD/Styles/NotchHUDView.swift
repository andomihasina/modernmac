import SwiftUI

/// `notch`: the HUD grows down out of the notch as one black shape, with
/// the symbol and the level bar in the part below it. On a screen without
/// a notch it is a floating black pill instead (SPEC §5.4). Always black
/// with white content.
struct NotchHUDView: View {
    // MARK: Tunable numbers (points)

    // Shape below the notch (measured from docs/reference/notch-*.png).
    /// How far the shape grows below the notch.
    static let dropHeight: CGFloat = 34
    static let bottomCornerRadius: CGFloat = 10
    /// Small outward curve where the shape meets the top edge of the screen,
    /// like the hardware notch has. 0 gives square top corners.
    static let topFlareRadius: CGFloat = 7

    // Content row.
    static let contentPadding: CGFloat = 16
    static let contentSpacing: CGFloat = 8
    /// The row sits a little above the centre of the dropped part.
    static let contentLift: CGFloat = 2
    static let symbolSize: CGFloat = 16
    static let symbolWeight = Font.Weight.semibold
    static let symbolBoxWidth: CGFloat = 23
    static let barHeight: CGFloat = 5
    static let barHoverHeight: CGFloat = 8
    static let barHitHeight: CGFloat = 28
    static let trackOpacity = 0.35
    static let percentageSize: CGFloat = 11
    static let percentageWidth: CGFloat = 32

    // Fallback pill (screens without a notch).
    static let pillSize = CGSize(width: 316, height: 32)
    static let pillTopMargin: CGFloat = 8
    static let pillPadding: CGFloat = 14
    static let pillSpacing: CGFloat = 10
    static let pillBarHitHeight: CGFloat = 26
    static let pillPercentageWidth: CGFloat = 34
    static let pillRimOpacity = 0.14
    static let pillShadow = (opacity: 0.25, radius: CGFloat(12), y: CGFloat(4))
    static let pillAppearScale: CGFloat = 0.9
    static let pillDisappearScale: CGFloat = 0.95

    // Panel around the notch shape.
    static let panelSidePadding: CGFloat = 24
    static let panelBottomPadding: CGFloat = 24

    // Motion.
    static let expandAnimation = Animation.spring(response: 0.4, dampingFraction: 0.75)
    /// The content appears shortly after the expansion starts…
    static let contentAppear = Animation.easeOut(duration: 0.14).delay(0.08)
    /// …and is gone before the collapse gets going.
    static let contentDisappear = Animation.easeOut(duration: 0.08)
    static let collapseDelay: TimeInterval = 0.06
    /// How long a collapse takes to settle before the panel is ordered out.
    static let collapseSettle: TimeInterval = 0.5
    static let pillDisappear = Animation.easeOut(duration: 0.2)
    static let levelAnimation = Animation.easeOut(duration: 0.12)

    /// At the notch nothing fades: the shape grows out of the notch and
    /// retracts into it, and only then is the panel ordered out.
    static let notchMotion = HUDMotion(
        appearFade: 0, disappearFade: 0, orderOutDelay: collapseDelay + collapseSettle)
    /// Reduce Motion, and the pill: fade.
    static let fadeMotion = HUDMotion(appearFade: 0.18, disappearFade: 0.2, orderOutDelay: 0.25)

    // MARK: Geometry for the panel

    static func placement(
        options: HUDOptions, screen: ScreenMetrics, reduceMotion: Bool
    ) -> HUDPlacement {
        switch NotchLayout.mode(for: screen) {
        case .notch(let notch):
            let expanded = NotchLayout.expandedRect(notch: notch, dropHeight: dropHeight)
            return HUDPlacement(
                panelFrame: NotchLayout.panelFrame(
                    expanded: expanded,
                    sidePadding: panelSidePadding, bottomPadding: panelBottomPadding),
                hitFrame: expanded,
                hoverHitFrame: expanded,
                hitCornerRadius: bottomCornerRadius,
                isOverMenuBar: true,
                motion: reduceMotion ? fadeMotion : notchMotion)
        case .pill:
            let pill = NotchLayout.pillRect(
                size: pillSize, screen: screen, topMargin: pillTopMargin)
            return HUDPlacement(
                panelFrame: HUDLayout.panelFrame(forShape: pill),
                hitFrame: pill,
                hoverHitFrame: pill,
                hitCornerRadius: pillSize.height / 2,
                isOverMenuBar: false,
                motion: fadeMotion)
        }
    }

    // MARK: View

    let model: HUDViewModel

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.hudReduceMotion) private var reduceMotionOverride
    @Environment(\.colorSchemeContrast) private var systemContrast
    @Environment(\.hudIncreaseContrast) private var contrastOverride

    private var reducesMotion: Bool { reduceMotionOverride ?? systemReduceMotion }
    private var increasesContrast: Bool { contrastOverride ?? (systemContrast == .increased) }

    var body: some View {
        Group {
            if let notch = model.notchSize {
                notchBody(notch)
            } else {
                pillBody
            }
        }
        // Black shape, white content, whatever the system appearance.
        .environment(\.colorScheme, .dark)
    }

    private var levelAnimation: Animation? {
        model.animatesLevel ? Self.levelAnimation : nil
    }

    // MARK: At the notch

    private func notchBody(_ notch: CGSize) -> some View {
        // With Reduce Motion the shape never changes size; the panel fades.
        let isExpanded = reducesMotion || model.phase == .shown
        let fullHeight = notch.height + Self.dropHeight
        let height = isExpanded ? fullHeight : notch.height
        let flare = isExpanded ? Self.topFlareRadius : 0

        return ZStack(alignment: .top) {
            NotchShape(flare: flare, bottomRadius: Self.bottomCornerRadius)
                .fill(Color.black)
                .frame(width: notch.width + 2 * flare, height: height)

            row(barHeight: Self.barHeight, hoverHeight: Self.barHoverHeight,
                hitHeight: Self.barHitHeight, percentageWidth: Self.percentageWidth,
                spacing: Self.contentSpacing)
                .padding(.horizontal, Self.contentPadding)
                .frame(width: notch.width, height: Self.dropHeight)
                .offset(y: -Self.contentLift)
                // With Reduce Motion the panel's fade carries the content too;
                // hiding it here would make it pop out ahead of the shape.
                .opacity(reducesMotion || model.phase == .shown ? 1 : 0)
                .animation(contentAnimation, value: model.phase)
                .frame(width: notch.width, height: fullHeight, alignment: .bottom)
                // The content stays put; the growing shape uncovers it.
                .mask(alignment: .top) {
                    NotchShape(flare: 0, bottomRadius: Self.bottomCornerRadius)
                        .frame(width: notch.width, height: height)
                }
        }
        .animation(notchPhaseAnimation, value: model.phase)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Symbol, bar and optional percentage: the same row at the notch and in the pill.
    private func row(
        barHeight: CGFloat, hoverHeight: CGFloat, hitHeight: CGFloat,
        percentageWidth: CGFloat, spacing: CGFloat
    ) -> some View {
        HStack(spacing: spacing) {
            HUDIcon(
                symbolName: model.state.symbolName,
                value: model.state.symbolValue,
                pointSize: Self.symbolSize,
                weight: Self.symbolWeight,
                boxWidth: Self.symbolBoxWidth)
            LevelBar(
                level: model.displayedLevel,
                height: model.isHovering || model.isDragging ? hoverHeight : barHeight,
                hitHeight: hitHeight,
                trackOpacity: Self.trackOpacity,
                levelAnimation: levelAnimation,
                onDrag: model.options.isInteractive ? model.onDragChanged : nil,
                onDragEnd: model.onDragEnded)
            if model.options.showsPercentage {
                Text(model.percentageText)
                    .font(.system(size: Self.percentageSize, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(width: percentageWidth, alignment: .trailing)
            }
        }
    }

    private var notchPhaseAnimation: Animation? {
        guard !reducesMotion else { return nil }
        switch model.phase {
        case .idle: return nil
        case .shown: return Self.expandAnimation
        case .leaving: return Self.expandAnimation.delay(Self.collapseDelay)
        }
    }

    private var contentAnimation: Animation? {
        guard !reducesMotion else { return nil }
        switch model.phase {
        case .idle: return nil
        case .shown: return Self.contentAppear
        case .leaving: return Self.contentDisappear
        }
    }

    // MARK: Pill

    private var pillBody: some View {
        row(barHeight: Self.barHeight, hoverHeight: Self.barHoverHeight,
            hitHeight: Self.pillBarHitHeight, percentageWidth: Self.pillPercentageWidth,
            spacing: Self.pillSpacing)
        .padding(.horizontal, Self.pillPadding)
        .frame(width: Self.pillSize.width, height: Self.pillSize.height)
        .background {
            Capsule()
                .fill(Color.black)
                .shadow(
                    color: .black.opacity(Self.pillShadow.opacity),
                    radius: Self.pillShadow.radius, y: Self.pillShadow.y)
        }
        .overlay {
            Capsule().strokeBorder(
                Color.white.opacity(increasesContrast ? 0.8 : Self.pillRimOpacity),
                lineWidth: increasesContrast ? 1.5 : 1)
        }
        .scaleEffect(pillScale, anchor: .top)
        .animation(pillPhaseAnimation, value: model.phase)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pillScale: CGFloat {
        guard !reducesMotion else { return 1 }
        switch model.phase {
        case .idle: return Self.pillAppearScale
        case .shown: return 1
        case .leaving: return Self.pillDisappearScale
        }
    }

    private var pillPhaseAnimation: Animation? {
        switch model.phase {
        case .idle: return nil
        case .shown: return Self.expandAnimation
        case .leaving: return Self.pillDisappear
        }
    }
}

/// The notch outline: square at the top edge of the screen apart from a
/// small outward flare, round at the bottom. `rect` includes the flares.
struct NotchShape: Shape {
    var flare: CGFloat
    var bottomRadius: CGFloat

    var animatableData: CGFloat {
        get { flare }
        set { flare = newValue }
    }

    nonisolated func path(in rect: CGRect) -> Path {
        let flare = max(0, min(flare, rect.width / 2, rect.height))
        let body = rect.insetBy(dx: flare, dy: 0)
        var path = UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius,
            topTrailingRadius: 0,
            style: .continuous
        ).path(in: body)

        guard flare > 0 else { return path }
        // Left flare: from the outer tip on the top edge, curving down into
        // the body's side.
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: body.minX, y: rect.minY + flare),
            control: CGPoint(x: body.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: body.minX, y: rect.minY))
        path.closeSubpath()
        // Right flare, mirrored.
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: body.maxX, y: rect.minY + flare),
            control: CGPoint(x: body.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: body.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
