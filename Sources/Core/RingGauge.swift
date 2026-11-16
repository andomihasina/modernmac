import Foundation

/// Pure geometry for the `circular` style's ring: an open arc with its gap
/// at the bottom, like a gauge (docs/reference/circular-*.png). The level
/// runs clockwise from the lower-left end to the lower-right end, and a
/// knob marks it.
///
/// Positions along the arc are fractions, 0 at the start and 1 at the end.
/// Angles are in degrees, clockwise from 12 o'clock.
enum RingGauge {
    /// How much of the circle the arc covers; the rest is the gap.
    static let sweep: Double = 260
    /// Where the arc starts: the gap is centred on 6 o'clock.
    static let startAngle: Double = 180 + (360 - sweep) / 2

    /// What to draw for a level.
    struct Trim: Equatable, Sendable {
        /// Where the knob sits.
        var knob: Double
        /// The filled part, from the start up to just before the knob; nil
        /// when there is no room for it.
        var progress: ClosedRange<Double>?
        /// The unfilled part, from just after the knob to the end; nil when
        /// there is no room for it.
        var track: ClosedRange<Double>?
    }

    /// Level → position along the arc. Anything outside 0…1 clamps; a
    /// level that is not a number reads as 0.
    static func fraction(forLevel level: Double) -> Double {
        guard !level.isNaN else { return 0 }
        return min(max(level, 0), 1)
    }

    /// Position along the arc → angle, 230° at the start to 490° (= 130°)
    /// at the end.
    static func angle(atFraction fraction: Double) -> Double {
        startAngle + min(max(fraction, 0), 1) * sweep
    }

    static func angle(forLevel level: Double) -> Double {
        angle(atFraction: fraction(forLevel: level))
    }

    /// - Parameter knobClearance: How far each arc stops short of the knob,
    ///   as a fraction of the sweep.
    static func trim(level: Double, knobClearance: Double) -> Trim {
        let knob = fraction(forLevel: level)
        let clearance = max(0, knobClearance.isNaN ? 0 : knobClearance)
        let progressEnd = knob - clearance
        let trackStart = knob + clearance
        return Trim(
            knob: knob,
            progress: progressEnd > 0 ? 0...progressEnd : nil,
            track: trackStart < 1 ? trackStart...1 : nil)
    }
}
