import XCTest
@testable import ModernMac

final class RingGaugeTests: XCTestCase {
    /// A clearance like the style's: about 7% of the sweep each side of the knob.
    private let clearance = 0.07

    // MARK: - Angles

    func testTheGapIsCentredAtTheBottom() {
        // 260° of arc leaves a 100° gap: 50° either side of 6 o'clock.
        XCTAssertEqual(RingGauge.startAngle, 230)
        XCTAssertEqual(RingGauge.angle(forLevel: 0), 230)
        XCTAssertEqual(RingGauge.angle(forLevel: 1), 490)  // = 130° on the dial
        XCTAssertEqual(RingGauge.angle(forLevel: 1) - 360, 360 - RingGauge.angle(forLevel: 0))
    }

    func testHalfIsAtTwelveOClock() {
        XCTAssertEqual(RingGauge.angle(forLevel: 0.5), 360)
    }

    func testAngleGrowsClockwiseWithTheLevel() {
        XCTAssertEqual(RingGauge.angle(forLevel: 0.25), 295)
        XCTAssertEqual(RingGauge.angle(forLevel: 0.75), 425)
        XCTAssertEqual(RingGauge.angle(atFraction: 0.1), 256)
    }

    func testLevelsOutsideTheRangeClamp() {
        XCTAssertEqual(RingGauge.fraction(forLevel: -0.2), 0)
        XCTAssertEqual(RingGauge.fraction(forLevel: 1.3), 1)
        XCTAssertEqual(RingGauge.fraction(forLevel: .infinity), 1)
        XCTAssertEqual(RingGauge.fraction(forLevel: -.infinity), 0)
        XCTAssertEqual(RingGauge.fraction(forLevel: .nan), 0)
        XCTAssertEqual(RingGauge.angle(forLevel: 7), 490)
        XCTAssertEqual(RingGauge.angle(atFraction: -1), 230)
    }

    // MARK: - Trim

    func testTrimInTheMiddle() {
        let trim = RingGauge.trim(level: 0.5, knobClearance: clearance)
        XCTAssertEqual(trim.knob, 0.5)
        XCTAssertEqual(trim.progress?.lowerBound, 0)
        XCTAssertEqual(trim.progress?.upperBound ?? 0, 0.43, accuracy: 1e-12)
        XCTAssertEqual(trim.track?.lowerBound ?? 0, 0.57, accuracy: 1e-12)
        XCTAssertEqual(trim.track?.upperBound, 1)
    }

    func testEmptyRingHasNoProgress() {
        let trim = RingGauge.trim(level: 0, knobClearance: clearance)
        XCTAssertEqual(trim.knob, 0)
        XCTAssertNil(trim.progress)
        XCTAssertEqual(trim.track, 0.07...1)
    }

    func testFullRingHasNoTrack() {
        let trim = RingGauge.trim(level: 1, knobClearance: clearance)
        XCTAssertEqual(trim.knob, 1)
        XCTAssertEqual(trim.progress?.lowerBound, 0)
        XCTAssertEqual(trim.progress?.upperBound ?? 0, 0.93, accuracy: 1e-12)
        XCTAssertNil(trim.track)
    }

    func testOneFineStepStillHasNoRoomForProgress() {
        // 1/64 is closer to the start than the knob's clearance.
        let trim = RingGauge.trim(level: 1.0 / 64, knobClearance: clearance)
        XCTAssertEqual(trim.knob, 1.0 / 64)
        XCTAssertNil(trim.progress)
        XCTAssertEqual(trim.track?.lowerBound ?? 0, 1.0 / 64 + clearance, accuracy: 1e-12)
    }

    func testProgressAppearsOnceTheKnobClearsTheStart() {
        XCTAssertNil(RingGauge.trim(level: clearance, knobClearance: clearance).progress)
        let trim = RingGauge.trim(level: 0.125, knobClearance: clearance)
        XCTAssertEqual(trim.progress?.lowerBound, 0)
        XCTAssertEqual(trim.progress?.upperBound ?? 0, 0.055, accuracy: 1e-12)
    }

    func testTrackDisappearsOnceTheKnobNearsTheEnd() {
        XCTAssertNil(RingGauge.trim(level: 1 - clearance, knobClearance: clearance).track)
        XCTAssertNil(RingGauge.trim(level: 63.0 / 64, knobClearance: clearance).track)
        XCTAssertNotNil(RingGauge.trim(level: 0.9, knobClearance: clearance).track)
    }

    func testTrimClampsTheLevel() {
        XCTAssertEqual(
            RingGauge.trim(level: -1, knobClearance: clearance),
            RingGauge.trim(level: 0, knobClearance: clearance))
        XCTAssertEqual(
            RingGauge.trim(level: 2, knobClearance: clearance),
            RingGauge.trim(level: 1, knobClearance: clearance))
        XCTAssertEqual(
            RingGauge.trim(level: .nan, knobClearance: clearance),
            RingGauge.trim(level: 0, knobClearance: clearance))
    }

    func testArcsNeverOverlapTheKnobOrLeaveTheGauge() {
        for step in 0...64 {
            let level = Double(step) / 64
            let trim = RingGauge.trim(level: level, knobClearance: clearance)
            if let progress = trim.progress {
                XCTAssertEqual(progress.lowerBound, 0)
                XCTAssertLessThanOrEqual(progress.upperBound, trim.knob - clearance + 1e-12)
            }
            if let track = trim.track {
                XCTAssertEqual(track.upperBound, 1)
                XCTAssertGreaterThanOrEqual(track.lowerBound, trim.knob + clearance - 1e-12)
            }
        }
    }

    func testWithoutClearanceTheArcsMeetAtTheKnob() {
        let trim = RingGauge.trim(level: 0.3, knobClearance: 0)
        XCTAssertEqual(trim.progress, 0...0.3)
        XCTAssertEqual(trim.track, 0.3...1)
        // A negative or broken clearance counts as none.
        XCTAssertEqual(RingGauge.trim(level: 0.3, knobClearance: -0.5), trim)
        XCTAssertEqual(RingGauge.trim(level: 0.3, knobClearance: .nan), trim)
    }
}
