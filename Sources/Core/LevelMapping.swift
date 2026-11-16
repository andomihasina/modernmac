import Foundation

/// Pointer input on a HUD → level.
enum LevelMapping {
    /// - Parameters:
    ///   - x: Pointer position measured from the bar's leading edge.
    ///   - trackWidth: Length of the bar.
    /// - Returns: 0…1, continuous (no grid snapping). Positions past either
    ///   end clamp, so a drag can overshoot the bar and still reach 0 and 1.
    static func level(atX x: Double, trackWidth: Double) -> Double {
        guard trackWidth > 0, x.isFinite else { return 0 }
        return min(max(x / trackWidth, 0), 1)
    }

    // MARK: - Disc (`circular`)

    /// Vertical drag or scroll on the disc: 1 pt = 0.5% (SPEC §5.4).
    static let discLevelPerPoint = 0.005
    /// One line of a wheel mouse counts as this many points: 4% a line.
    static let pointsPerScrollLine = 8.0

    /// A vertical drag on the disc. The level is tied to where the drag
    /// started: after overshooting an end, it moves again as soon as the
    /// pointer comes back past the point where it reached that end.
    ///
    /// - Parameters:
    ///   - start: Level when the drag began.
    ///   - points: Distance dragged, up positive.
    static func level(
        from start: Double, draggedUpBy points: Double,
        perPoint: Double = discLevelPerPoint
    ) -> Double {
        let start = clamped(start)
        guard points.isFinite else { return start }
        return clamped(start + points * perPoint)
    }

    /// One scroll event over the disc. Fingers (or the wheel) moving up
    /// raise the level whatever the "natural scrolling" setting says, so
    /// scrolling matches dragging. Each event steps from the current level,
    /// so scrolling past an end is forgotten and the way back starts at once.
    ///
    /// - Parameters:
    ///   - deltaY: `NSEvent.scrollingDeltaY`.
    ///   - isPrecise: `hasPreciseScrollingDeltas`: points (trackpad) or
    ///     lines (wheel).
    ///   - isInvertedFromDevice: `isDirectionInvertedFromDevice`, true with
    ///     natural scrolling.
    static func level(
        from current: Double, scrolledBy deltaY: Double,
        isPrecise: Bool, isInvertedFromDevice: Bool,
        perPoint: Double = discLevelPerPoint
    ) -> Double {
        let current = clamped(current)
        guard deltaY.isFinite else { return current }
        let points = isPrecise ? deltaY : deltaY * pointsPerScrollLine
        let upward = isInvertedFromDevice ? -points : points
        return clamped(current + upward * perPoint)
    }

    private static func clamped(_ level: Double) -> Double {
        guard !level.isNaN else { return 0 }
        return min(max(level, 0), 1)
    }
}
