import XCTest
@testable import ModernMac

final class StepMathTests: XCTestCase {
    private let accuracy = 1e-12

    func testNormalStepIsOneSixteenth() {
        XCTAssertEqual(StepMath.step(0.5, .up, .normal), 9.0 / 16, accuracy: accuracy)
        XCTAssertEqual(StepMath.step(0.5, .down, .normal), 7.0 / 16, accuracy: accuracy)
    }

    func testFineStepIsOneSixtyFourth() {
        XCTAssertEqual(StepMath.step(0.5, .up, .fine), 33.0 / 64, accuracy: accuracy)
        XCTAssertEqual(StepMath.step(0.5, .down, .fine), 31.0 / 64, accuracy: accuracy)
    }

    func testClampsAtZero() {
        XCTAssertEqual(StepMath.step(0, .down, .normal), 0)
        XCTAssertEqual(StepMath.step(0, .down, .fine), 0)
        XCTAssertEqual(StepMath.step(1.0 / 16, .down, .normal), 0)
        XCTAssertEqual(StepMath.step(0, .up, .normal), 1.0 / 16, accuracy: accuracy)
    }

    func testClampsAtOne() {
        XCTAssertEqual(StepMath.step(1, .up, .normal), 1)
        XCTAssertEqual(StepMath.step(1, .up, .fine), 1)
        XCTAssertEqual(StepMath.step(15.0 / 16, .up, .normal), 1)
        XCTAssertEqual(StepMath.step(1, .down, .normal), 15.0 / 16, accuracy: accuracy)
    }

    func testLevelBetweenGridPointsSnapsBeforeStepping() {
        // 0.53 × 16 = 8.48 → 8, so up gives 9/16 and down gives 7/16.
        XCTAssertEqual(StepMath.step(0.53, .up, .normal), 9.0 / 16, accuracy: accuracy)
        XCTAssertEqual(StepMath.step(0.53, .down, .normal), 7.0 / 16, accuracy: accuracy)
        // 0.55 × 16 = 8.8 → 9, so up gives 10/16 and down gives 8/16.
        XCTAssertEqual(StepMath.step(0.55, .up, .normal), 10.0 / 16, accuracy: accuracy)
        XCTAssertEqual(StepMath.step(0.55, .down, .normal), 8.0 / 16, accuracy: accuracy)
    }

    func testFineStepFromALevelOffTheFineGrid() {
        // 0.53 × 64 = 33.92 → 34.
        XCTAssertEqual(StepMath.step(0.53, .up, .fine), 35.0 / 64, accuracy: accuracy)
        XCTAssertEqual(StepMath.step(0.53, .down, .fine), 33.0 / 64, accuracy: accuracy)
    }

    func testFineStepsMoveBetweenNormalGridPoints() {
        var level = 8.0 / 16
        for _ in 0..<4 { level = StepMath.step(level, .up, .fine) }
        XCTAssertEqual(level, 9.0 / 16, accuracy: accuracy)
    }

    func testNormalStepAfterFineStepsReturnsToTheNormalGrid() {
        let offGrid = StepMath.step(0.5, .up, .fine)  // 33/64 = 8.25/16 → snaps to 8
        XCTAssertEqual(StepMath.step(offGrid, .up, .normal), 9.0 / 16, accuracy: accuracy)
    }

    func testHardwareFloatNoiseDoesNotDrift() {
        // Read-backs logged in Phase 0.
        XCTAssertEqual(StepMath.step(0.18750001, .up, .normal), 0.25, accuracy: accuracy)
        XCTAssertEqual(StepMath.step(0.37500003, .down, .normal), 0.3125, accuracy: accuracy)
        XCTAssertEqual(StepMath.step(0.87499994, .up, .normal), 0.9375, accuracy: accuracy)
    }

    func testSixteenStepsCoverTheWholeRange() {
        var level = 0.0
        for _ in 0..<16 { level = StepMath.step(level, .up, .normal) }
        XCTAssertEqual(level, 1)
        for _ in 0..<16 { level = StepMath.step(level, .down, .normal) }
        XCTAssertEqual(level, 0)
    }

    func testOutOfRangeAndNonFiniteInputs() {
        XCTAssertEqual(StepMath.step(1.4, .up, .normal), 1)
        XCTAssertEqual(StepMath.step(1.4, .down, .normal), 15.0 / 16, accuracy: accuracy)
        XCTAssertEqual(StepMath.step(-0.3, .down, .normal), 0)
        XCTAssertEqual(StepMath.step(-0.3, .up, .normal), 1.0 / 16, accuracy: accuracy)
        XCTAssertEqual(StepMath.step(.nan, .up, .normal), 1.0 / 16, accuracy: accuracy)
        XCTAssertEqual(StepMath.step(.infinity, .down, .normal), 0)
    }
}
