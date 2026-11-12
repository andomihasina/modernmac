import XCTest
@testable import ModernMac

final class LevelMappingTests: XCTestCase {
    func testEndsOfTheBar() {
        XCTAssertEqual(LevelMapping.level(atX: 0, trackWidth: 200), 0)
        XCTAssertEqual(LevelMapping.level(atX: 200, trackWidth: 200), 1)
    }

    func testPositionsAlongTheBar() {
        XCTAssertEqual(LevelMapping.level(atX: 100, trackWidth: 200), 0.5)
        XCTAssertEqual(LevelMapping.level(atX: 50, trackWidth: 200), 0.25)
        XCTAssertEqual(LevelMapping.level(atX: 150, trackWidth: 200), 0.75)
    }

    func testIsContinuousNotSnappedToTheKeyGrid() {
        // 37 / 200 lies between the 1/16 grid points 0.125 and 0.1875.
        XCTAssertEqual(LevelMapping.level(atX: 37, trackWidth: 200), 0.185, accuracy: 1e-12)
        XCTAssertEqual(LevelMapping.level(atX: 0.5, trackWidth: 200), 0.0025, accuracy: 1e-12)
    }

    func testPointerPastTheEndsClamps() {
        XCTAssertEqual(LevelMapping.level(atX: -30, trackWidth: 200), 0)
        XCTAssertEqual(LevelMapping.level(atX: 260, trackWidth: 200), 1)
    }

    func testDegenerateInputGivesZero() {
        XCTAssertEqual(LevelMapping.level(atX: 10, trackWidth: 0), 0)
        XCTAssertEqual(LevelMapping.level(atX: 10, trackWidth: -5), 0)
        XCTAssertEqual(LevelMapping.level(atX: .nan, trackWidth: 200), 0)
        XCTAssertEqual(LevelMapping.level(atX: .infinity, trackWidth: 200), 0)
    }

    func testScalesWithTheBarWidth() {
        XCTAssertEqual(LevelMapping.level(atX: 62, trackWidth: 248), 0.25)
        XCTAssertEqual(LevelMapping.level(atX: 62, trackWidth: 124), 0.5)
    }
}
