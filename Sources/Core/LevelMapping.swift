import Foundation

/// Pointer position on a level bar → level.
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
}
