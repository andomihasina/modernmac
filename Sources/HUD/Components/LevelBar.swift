import SwiftUI

/// A knob-less level bar: capsule track with a fill. Shared by the styles.
///
/// With `onDrag` set, pressing or dragging anywhere in the bar's hit area
/// reports the level under the pointer.
struct LevelBar: View {
    static let heightAnimation = Animation.easeOut(duration: 0.15)

    /// 0…1.
    var level: Double
    /// Thickness of the bar.
    var height: CGFloat
    /// Height of the area that takes the pointer; the bar is centred in it.
    var hitHeight: CGFloat
    var trackOpacity: Double
    /// How a level change animates; `nil` follows the level directly.
    var levelAnimation: Animation?
    var onDrag: ((Double) -> Void)?
    var onDragEnd: (() -> Void)?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack {
                Capsule().fill(Color.primary.opacity(trackOpacity))
                BarFill(fraction: min(max(level, 0), 1))
                    .fill(Color.primary)
                    .animation(levelAnimation, value: level)
            }
            .clipShape(Capsule())
            .frame(height: height)
            .animation(Self.heightAnimation, value: height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onDrag?(LevelMapping.level(atX: value.location.x, trackWidth: width))
                    }
                    .onEnded { _ in onDragEnd?() },
                including: onDrag == nil ? .none : .all)
        }
        .frame(height: hitHeight)
    }
}

/// The filled part: as wide as the level, with a round leading end. Below
/// one bar-height of width the round end slides in from the left, so tiny
/// levels still read as a sliver instead of a dot.
private struct BarFill: Shape {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    nonisolated func path(in rect: CGRect) -> Path {
        let filled = rect.width * fraction
        guard filled > 0 else { return Path() }
        let width = max(filled, rect.height)
        let capsule = CGRect(
            x: rect.minX + filled - width, y: rect.minY, width: width, height: rect.height)
        return Capsule().path(in: capsule)
    }
}
