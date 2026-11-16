import SwiftUI

/// `circular`: a glass disc with the symbol in the middle and the level on
/// a ring around it (SPEC §5.4). The ring is an open gauge with its gap at
/// the bottom, where the optional number sits, as in
/// docs/reference/circular-*.png. Dragging up or down on the disc, or
/// scrolling over it, changes the level.
struct CircularHUDView: View {
    // MARK: Tunable numbers (points)

    // Disc.
    static let diameter: CGFloat = 84

    // Ring (proportions measured from docs/reference/circular-*.png).
    /// From the disc's edge to the ring's outer edge.
    static let ringInset: CGFloat = 7.5
    static let ringLineWidth: CGFloat = 7
    static let knobRadius: CGFloat = 4
    /// Clear space between the knob and the ends of the arcs beside it.
    static let knobGap: CGFloat = 2.5
    static let progressOpacity = 1.0
    static let trackOpacity = 0.18

    // Content.
    static let symbolSize: CGFloat = 22
    static let symbolWeight = Font.Weight.semibold
    static let symbolBoxWidth: CGFloat = 40
    static let numberSize: CGFloat = 13
    /// The number sits in the ring's gap, this far below the centre.
    static let numberOffsetY: CGFloat = 27

    // Interaction.
    static let hoverScale: CGFloat = 1.06
    static let hoverAnimation = Animation.easeOut(duration: 0.15)
    /// A press that does not move is not a drag.
    static let dragMinimumDistance: CGFloat = 1

    // Motion.
    static let appearScale: CGFloat = 0.6
    static let appearAnimation = Animation.spring(response: 0.35, dampingFraction: 0.7)
    static let disappearScale: CGFloat = 0.8
    static let disappearAnimation = Animation.easeOut(duration: 0.2)
    static let levelAnimation = Animation.easeOut(duration: 0.15)
    /// Fade of the whole panel, which carries the opacity part of appear and disappear.
    static let motion = HUDMotion(appearFade: 0.18, disappearFade: 0.2, orderOutDelay: 0.25)

    /// Radius of the ring's centre line.
    static var ringRadius: CGFloat { diameter / 2 - ringInset - ringLineWidth / 2 }

    /// How far the arcs stop short of the knob, as a fraction of the sweep:
    /// the knob, the gap, and the arc's round cap.
    static var knobClearance: Double {
        let radians = Double((knobRadius + knobGap + ringLineWidth / 2) / ringRadius)
        return radians * 180 / .pi / RingGauge.sweep
    }

    // MARK: Geometry for the panel

    static func placement(
        options: HUDOptions, screen: ScreenMetrics, reduceMotion: Bool
    ) -> HUDPlacement {
        let frame = HUDLayout.shapeFrame(
            size: CGSize(width: diameter, height: diameter),
            position: options.position, screen: screen)
        // The disc grows under the pointer; the pointer stays "on" it
        // across the larger disc.
        let grow = reduceMotion ? 0 : diameter * (hoverScale - 1) / 2
        return HUDPlacement(
            panelFrame: HUDLayout.panelFrame(forShape: frame),
            hitFrame: frame,
            hoverHitFrame: frame.insetBy(dx: -grow, dy: -grow),
            // Half the side or more: the hit test treats it as a circle.
            hitCornerRadius: diameter,
            isOverMenuBar: false,
            motion: motion)
    }

    // MARK: View

    let model: HUDViewModel

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.hudReduceMotion) private var reduceMotionOverride
    /// Level when the current drag began.
    @State private var dragStartLevel: Double?

    private var reducesMotion: Bool { reduceMotionOverride ?? systemReduceMotion }

    var body: some View {
        ZStack {
            ring
            HUDIcon(
                symbolName: model.state.symbolName,
                value: model.state.symbolValue,
                pointSize: Self.symbolSize,
                weight: Self.symbolWeight,
                boxWidth: Self.symbolBoxWidth,
                alignment: .center)
            if model.options.showsPercentage {
                Text(model.levelNumberText)
                    .font(.system(size: Self.numberSize, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .offset(y: Self.numberOffsetY)
            }
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .background(GlassBackground(shape: .capsule))
        .contentShape(Circle())
        .gesture(drag, including: model.options.isInteractive ? .all : .none)
        .scaleEffect(hoverScale)
        .animation(Self.hoverAnimation, value: hoverScale)
        .scaleEffect(phaseScale)
        .animation(phaseAnimation, value: model.phase)
    }

    // MARK: Ring

    private var ring: some View {
        let level = model.displayedLevel
        let stroke = StrokeStyle(lineWidth: Self.ringLineWidth, lineCap: .round)
        let side = Self.ringRadius * 2
        return ZStack {
            RingArc(part: .track, level: level, knobClearance: Self.knobClearance)
                .stroke(Color.primary.opacity(Self.trackOpacity), style: stroke)
            RingArc(part: .progress, level: level, knobClearance: Self.knobClearance)
                .stroke(Color.primary.opacity(Self.progressOpacity), style: stroke)
            RingKnob(level: level, radius: Self.knobRadius)
                .fill(Color.primary)
        }
        .frame(width: side, height: side)
        .animation(model.animatesLevel ? Self.levelAnimation : nil, value: level)
    }

    // MARK: Drag

    private var drag: some Gesture {
        // Global space: the disc's own space scales with hover.
        DragGesture(minimumDistance: Self.dragMinimumDistance, coordinateSpace: .global)
            .onChanged { value in
                // The real level, also while muted: a drag unmutes and
                // carries on from there, like the keys.
                let start = dragStartLevel ?? model.state.level
                if dragStartLevel == nil { dragStartLevel = start }
                model.onDragChanged?(
                    LevelMapping.level(from: start, draggedUpBy: -value.translation.height))
            }
            .onEnded { _ in
                dragStartLevel = nil
                model.onDragEnded?()
            }
    }

    // MARK: Appear, disappear, hover

    private var hoverScale: CGFloat {
        guard !reducesMotion, model.isHovering || model.isDragging else { return 1 }
        return Self.hoverScale
    }

    private var phaseScale: CGFloat {
        guard !reducesMotion else { return 1 }
        switch model.phase {
        case .idle: return Self.appearScale
        case .shown: return 1
        case .leaving: return Self.disappearScale
        }
    }

    private var phaseAnimation: Animation? {
        switch model.phase {
        case .idle: return nil
        case .shown: return Self.appearAnimation
        case .leaving: return Self.disappearAnimation
        }
    }
}

/// One of the ring's two arcs, along the centre line of the stroke. `rect`
/// is the square around the ring's centre line.
struct RingArc: Shape {
    enum Part: Sendable {
        /// From the start of the gauge to the knob.
        case progress
        /// From the knob to the end of the gauge.
        case track
    }

    var part: Part
    var level: Double
    var knobClearance: Double

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    nonisolated func path(in rect: CGRect) -> Path {
        let trim = RingGauge.trim(level: level, knobClearance: knobClearance)
        guard let range = part == .progress ? trim.progress : trim.track else { return Path() }
        var path = Path()
        // SwiftUI measures angles from 3 o'clock, and with y pointing down
        // `clockwise: false` runs clockwise on screen.
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: min(rect.width, rect.height) / 2,
            startAngle: .degrees(RingGauge.angle(atFraction: range.lowerBound) - 90),
            endAngle: .degrees(RingGauge.angle(atFraction: range.upperBound) - 90),
            clockwise: false)
        return path
    }
}

/// The dot that marks the level on the ring. Animating `level` moves it
/// along the arc, not straight across the disc.
struct RingKnob: Shape {
    var level: Double
    var radius: CGFloat

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    nonisolated func path(in rect: CGRect) -> Path {
        let angle = RingGauge.angle(forLevel: level) * .pi / 180
        let ringRadius = Double(min(rect.width, rect.height) / 2)
        let center = CGPoint(
            x: Double(rect.midX) + ringRadius * sin(angle),
            y: Double(rect.midY) - ringRadius * cos(angle))
        return Path(ellipseIn: CGRect(
            x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }
}
