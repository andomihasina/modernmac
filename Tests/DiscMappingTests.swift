import XCTest
@testable import ModernMac

/// Drag and scroll on the `circular` disc → level.
final class DiscMappingTests: XCTestCase {
    // MARK: - Drag

    func testOnePointIsHalfAPercent() {
        XCTAssertEqual(LevelMapping.discLevelPerPoint, 0.005)
        XCTAssertEqual(LevelMapping.level(from: 0.5, draggedUpBy: 1), 0.505, accuracy: 1e-12)
        XCTAssertEqual(LevelMapping.level(from: 0.5, draggedUpBy: -1), 0.495, accuracy: 1e-12)
    }

    func testDraggingUpRaisesAndDownLowers() {
        XCTAssertEqual(LevelMapping.level(from: 0.5, draggedUpBy: 40), 0.7, accuracy: 1e-12)
        XCTAssertEqual(LevelMapping.level(from: 0.5, draggedUpBy: -40), 0.3, accuracy: 1e-12)
    }

    func testNoMovementKeepsTheLevel() {
        XCTAssertEqual(LevelMapping.level(from: 0.3125, draggedUpBy: 0), 0.3125)
    }

    func testFullRangeTakesTwoHundredPoints() {
        XCTAssertEqual(LevelMapping.level(from: 0, draggedUpBy: 200), 1, accuracy: 1e-12)
        XCTAssertEqual(LevelMapping.level(from: 1, draggedUpBy: -200), 0, accuracy: 1e-12)
    }

    func testDragClampsAtBothEnds() {
        XCTAssertEqual(LevelMapping.level(from: 0.9, draggedUpBy: 100), 1)
        XCTAssertEqual(LevelMapping.level(from: 0.1, draggedUpBy: -100), 0)
        XCTAssertEqual(LevelMapping.level(from: 0.5, draggedUpBy: 10_000), 1)
        XCTAssertEqual(LevelMapping.level(from: 0.5, draggedUpBy: -10_000), 0)
    }

    func testDragIsTiedToWhereItStarted() {
        // 100 pt up from 0.9 overshoots by 80 pt; coming back 80 pt is
        // still at the top, and only then does the level follow again.
        XCTAssertEqual(LevelMapping.level(from: 0.9, draggedUpBy: 20), 1, accuracy: 1e-12)
        XCTAssertEqual(LevelMapping.level(from: 0.9, draggedUpBy: 10), 0.95, accuracy: 1e-12)
    }

    func testDragIsContinuousNotSnappedToTheKeyGrid() {
        XCTAssertEqual(LevelMapping.level(from: 0.5, draggedUpBy: 0.5), 0.5025, accuracy: 1e-12)
    }

    func testDragFromAStartOutsideTheRange() {
        XCTAssertEqual(LevelMapping.level(from: 1.4, draggedUpBy: -20), 0.9, accuracy: 1e-12)
        XCTAssertEqual(LevelMapping.level(from: -0.3, draggedUpBy: 20), 0.1, accuracy: 1e-12)
        XCTAssertEqual(LevelMapping.level(from: .nan, draggedUpBy: 20), 0.1, accuracy: 1e-12)
    }

    func testBrokenDragDistanceKeepsTheStart() {
        XCTAssertEqual(LevelMapping.level(from: 0.4, draggedUpBy: .nan), 0.4)
        XCTAssertEqual(LevelMapping.level(from: 0.4, draggedUpBy: .infinity), 0.4)
    }

    func testCustomDragRate() {
        XCTAssertEqual(
            LevelMapping.level(from: 0.5, draggedUpBy: 10, perPoint: 0.01), 0.6, accuracy: 1e-12)
    }

    // MARK: - Scroll

    private func scroll(
        from level: Double, by deltaY: Double, precise: Bool = true, natural: Bool = false
    ) -> Double {
        LevelMapping.level(
            from: level, scrolledBy: deltaY, isPrecise: precise, isInvertedFromDevice: natural)
    }

    func testTrackpadScrollIsHalfAPercentAPoint() {
        XCTAssertEqual(scroll(from: 0.5, by: 1), 0.505, accuracy: 1e-12)
        XCTAssertEqual(scroll(from: 0.5, by: 20), 0.6, accuracy: 1e-12)
        XCTAssertEqual(scroll(from: 0.5, by: -20), 0.4, accuracy: 1e-12)
    }

    func testFingersUpRaiseTheLevelWithNaturalScrollingToo() {
        // With natural scrolling, fingers moving up report a negative delta.
        XCTAssertEqual(scroll(from: 0.5, by: -20, natural: true), 0.6, accuracy: 1e-12)
        XCTAssertEqual(scroll(from: 0.5, by: 20, natural: true), 0.4, accuracy: 1e-12)
    }

    func testWheelLinesCountAsEightPoints() {
        XCTAssertEqual(LevelMapping.pointsPerScrollLine, 8)
        XCTAssertEqual(scroll(from: 0.5, by: 1, precise: false), 0.54, accuracy: 1e-12)
        XCTAssertEqual(scroll(from: 0.5, by: -1, precise: false), 0.46, accuracy: 1e-12)
        XCTAssertEqual(scroll(from: 0.5, by: -1, precise: false, natural: true), 0.54, accuracy: 1e-12)
        XCTAssertEqual(scroll(from: 0.5, by: 0.1, precise: false), 0.504, accuracy: 1e-12)
    }

    func testScrollClampsAtBothEnds() {
        XCTAssertEqual(scroll(from: 0.95, by: 50), 1)
        XCTAssertEqual(scroll(from: 0.05, by: -50), 0)
        XCTAssertEqual(scroll(from: 0.5, by: 30, precise: false), 1)
    }

    func testScrollPastAnEndIsForgotten() {
        // Each event steps from the level reached, so the way back starts
        // at once however far the scroll overshot.
        let top = scroll(from: 0.9, by: 500)
        XCTAssertEqual(top, 1)
        XCTAssertEqual(scroll(from: top, by: -10), 0.95, accuracy: 1e-12)
    }

    func testScrollStepsAddUp() {
        var level = 0.25
        for _ in 0..<10 { level = scroll(from: level, by: 3) }
        XCTAssertEqual(level, 0.4, accuracy: 1e-12)
    }

    func testZeroOrBrokenScrollKeepsTheLevel() {
        XCTAssertEqual(scroll(from: 0.4, by: 0), 0.4)
        XCTAssertEqual(scroll(from: 0.4, by: .nan), 0.4)
        XCTAssertEqual(scroll(from: 0.4, by: -.infinity), 0.4)
        XCTAssertEqual(scroll(from: 1.2, by: 0), 1)
    }
}
