import SwiftUI

/// `tahoe`: the macOS 26 look. A glass capsule near the top-right corner
/// with the symbol and a level bar (SPEC §5.4).
struct TahoeHUDView: View {
    // MARK: Tunable numbers (points)

    // Shape.
    static let width: CGFloat = 280
    static let height: CGFloat = 44
    /// With "Show device name": a rounded rectangle instead of a capsule.
    static let namedHeight: CGFloat = 64
    static let namedCornerRadius: CGFloat = 22

    // Content.
    static let horizontalPadding: CGFloat = 16
    static let spacing: CGFloat = 12
    static let symbolSize: CGFloat = 17
    static let symbolWeight = Font.Weight.semibold
    /// Box the symbol sits in; wide enough for the speaker with three waves.
    static let symbolBoxWidth: CGFloat = 26
    static let percentageSize: CGFloat = 12
    /// Fits "100%" so the bar keeps its length as the digits change.
    static let percentageWidth: CGFloat = 38
    static let nameSize: CGFloat = 12
    static let nameSpacing: CGFloat = 5

    // Level bar.
    static let barHeight: CGFloat = 6
    static let barHoverHeight: CGFloat = 10
    static let barHitHeight: CGFloat = 32
    static let trackOpacity = 0.2

    // Motion.
    static let appearScale: CGFloat = 0.9
    static let appearOffsetY: CGFloat = -8
    static let appearAnimation = Animation.spring(response: 0.35, dampingFraction: 0.8)
    static let disappearScale: CGFloat = 0.95
    static let disappearAnimation = Animation.easeOut(duration: 0.2)
    static let levelAnimation = Animation.easeOut(duration: 0.12)
    /// Fade of the whole panel, which carries the opacity part of appear and disappear.
    static let motion = HUDMotion(appearFade: 0.18, disappearFade: 0.2)

    // MARK: Geometry for the panel

    static func shapeSize(options: HUDOptions) -> CGSize {
        CGSize(width: width, height: options.showsDeviceName ? namedHeight : height)
    }

    static func shape(options: HUDOptions) -> HUDShape {
        options.showsDeviceName ? .rounded(namedCornerRadius) : .capsule
    }

    // MARK: View

    let model: HUDViewModel

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.hudReduceMotion) private var reduceMotionOverride

    private var reducesMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

    var body: some View {
        let options = model.options
        let size = Self.shapeSize(options: options)

        content
            .padding(.horizontal, Self.horizontalPadding)
            .frame(width: size.width, height: size.height)
            .background(GlassBackground(shape: Self.shape(options: options)))
            .scaleEffect(scale, anchor: anchor)
            .offset(y: offsetY)
            .animation(phaseAnimation, value: model.phase)
    }

    @ViewBuilder
    private var content: some View {
        if model.options.showsDeviceName {
            VStack(alignment: .leading, spacing: Self.nameSpacing) {
                Text(model.deviceLabel)
                    .font(.system(size: Self.nameSize, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                row.frame(height: Self.symbolSize + 4)
            }
        } else {
            row
        }
    }

    private var row: some View {
        HStack(spacing: Self.spacing) {
            HUDIcon(
                symbolName: model.state.symbolName,
                value: model.state.symbolValue,
                pointSize: Self.symbolSize,
                weight: Self.symbolWeight,
                boxWidth: Self.symbolBoxWidth)

            LevelBar(
                level: model.displayedLevel,
                height: model.isHovering || model.isDragging ? Self.barHoverHeight : Self.barHeight,
                hitHeight: Self.barHitHeight,
                trackOpacity: Self.trackOpacity,
                levelAnimation: model.animatesLevel ? Self.levelAnimation : nil,
                onDrag: model.options.isInteractive ? model.onDragChanged : nil,
                onDragEnd: model.onDragEnded)

            if model.options.showsPercentage {
                Text(model.percentageText)
                    .font(.system(size: Self.percentageSize, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(width: Self.percentageWidth, alignment: .trailing)
            }
        }
    }

    // MARK: Appear and disappear

    private var scale: CGFloat {
        guard !reducesMotion else { return 1 }
        switch model.phase {
        case .idle: return Self.appearScale
        case .shown: return 1
        case .leaving: return Self.disappearScale
        }
    }

    private var offsetY: CGFloat {
        guard !reducesMotion, model.phase == .idle else { return 0 }
        // Slides in from the screen edge it sits against.
        return model.options.position == .bottomCenter ? -Self.appearOffsetY : Self.appearOffsetY
    }

    private var phaseAnimation: Animation? {
        switch model.phase {
        case .idle: return nil
        case .shown: return Self.appearAnimation
        case .leaving: return Self.disappearAnimation
        }
    }

    private var anchor: UnitPoint {
        switch model.options.position {
        case .topRight: return .topTrailing
        case .topLeft: return .topLeading
        case .topCenter: return .top
        case .bottomCenter: return .bottom
        }
    }
}
