import XCTest
@testable import ModernMac

final class HUDLayoutTests: XCTestCase {
    private let capsule = CGSize(width: 280, height: 44)

    /// Ando's MacBook Air: notch, menu bar on top, Dock at the bottom (FINDINGS V6).
    private let notched = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 1470, height: 956),
        visibleFrame: CGRect(x: 0, y: 58, width: 1470, height: 861),
        safeAreaTop: 32)

    /// A second display to the right with no menu bar and no Dock.
    private let bare = ScreenMetrics(
        frame: CGRect(x: 1470, y: -124, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 1470, y: -124, width: 1920, height: 1080))

    private func shape(_ position: HUDPosition, on screen: ScreenMetrics) -> CGRect {
        HUDLayout.shapeFrame(size: capsule, position: position, screen: screen)
    }

    // MARK: - Screen with a menu bar

    func testTopRightSitsBelowTheMenuBar() {
        // 10 from the right edge, 10 below visibleFrame.maxY (919).
        XCTAssertEqual(shape(.topRight, on: notched), CGRect(x: 1180, y: 865, width: 280, height: 44))
    }

    func testTopLeftOnScreenWithMenuBar() {
        XCTAssertEqual(shape(.topLeft, on: notched), CGRect(x: 10, y: 865, width: 280, height: 44))
    }

    func testTopCenterOnScreenWithMenuBar() {
        XCTAssertEqual(shape(.topCenter, on: notched), CGRect(x: 595, y: 865, width: 280, height: 44))
    }

    func testBottomCenterSitsAboveTheDock() {
        // 10 above visibleFrame.minY (58).
        XCTAssertEqual(shape(.bottomCenter, on: notched), CGRect(x: 595, y: 68, width: 280, height: 44))
    }

    // MARK: - Screen without a menu bar

    func testTopRightOnScreenWithoutMenuBar() {
        // Right edge 3390, top 956.
        XCTAssertEqual(shape(.topRight, on: bare), CGRect(x: 3100, y: 902, width: 280, height: 44))
    }

    func testTopLeftOnScreenWithoutMenuBar() {
        XCTAssertEqual(shape(.topLeft, on: bare), CGRect(x: 1480, y: 902, width: 280, height: 44))
    }

    func testTopCenterOnScreenWithoutMenuBar() {
        XCTAssertEqual(shape(.topCenter, on: bare), CGRect(x: 2290, y: 902, width: 280, height: 44))
    }

    func testBottomCenterOnScreenWithoutMenuBar() {
        XCTAssertEqual(shape(.bottomCenter, on: bare), CGRect(x: 2290, y: -114, width: 280, height: 44))
    }

    // MARK: - Other screen shapes

    func testFullScreenOnNotchedDisplayStaysBelowTheNotchStrip() {
        // Menu bar hidden: visibleFrame covers the screen, but the top 32
        // points are the black strip beside the notch.
        var fullScreen = notched
        fullScreen.visibleFrame = fullScreen.frame
        XCTAssertEqual(shape(.topRight, on: fullScreen).maxY, 956 - 32 - 10)
        XCTAssertEqual(shape(.bottomCenter, on: fullScreen).minY, 10)
    }

    func testDockOnTheRightPushesTheShapeLeft() {
        var docked = bare
        docked.visibleFrame.size.width -= 70
        XCTAssertEqual(shape(.topRight, on: docked).maxX, 3390 - 70 - 10)
    }

    func testTallerShapeHangsFromTheSameTopEdge() {
        let named = HUDLayout.shapeFrame(
            size: CGSize(width: 280, height: 64), position: .topRight, screen: notched)
        XCTAssertEqual(named.maxY, shape(.topRight, on: notched).maxY)
        XCTAssertEqual(named.minY, 845)
    }

    func testOriginIsRoundedToWholePoints() {
        let odd = HUDLayout.shapeFrame(
            size: CGSize(width: 281, height: 44), position: .topCenter, screen: notched)
        XCTAssertEqual(odd.minX, odd.minX.rounded())
    }

    // MARK: - Panel

    func testPanelIsTheShapePlusTheCanvas() {
        let panel = HUDLayout.panelFrame(shapeSize: capsule, position: .topRight, screen: notched)
        let padding = HUDLayout.canvasPadding
        XCTAssertEqual(panel, CGRect(
            x: 1180 - padding, y: 865 - padding,
            width: 280 + 2 * padding, height: 44 + 2 * padding))
    }

    func testShapeIsCentredInThePanel() {
        for position in HUDPosition.allCases {
            for screen in [notched, bare] {
                let shape = HUDLayout.shapeFrame(size: capsule, position: position, screen: screen)
                let panel = HUDLayout.panelFrame(
                    shapeSize: capsule, position: position, screen: screen)
                XCTAssertEqual(panel.midX, shape.midX, "\(position)")
                XCTAssertEqual(panel.midY, shape.midY, "\(position)")
            }
        }
    }

    // MARK: - Hit testing the shape

    private let hit = CGRect(x: 100, y: 200, width: 280, height: 44)

    private func contains(_ x: CGFloat, _ y: CGFloat, radius: CGFloat = 22) -> Bool {
        HUDLayout.shape(hit, cornerRadius: radius, contains: CGPoint(x: x, y: y))
    }

    func testPointsInsideTheCapsule() {
        XCTAssertTrue(contains(240, 222))
        XCTAssertTrue(contains(100, 222), "leftmost point of the capsule")
        XCTAssertTrue(contains(380, 222), "rightmost point of the capsule")
        XCTAssertTrue(contains(240, 200), "bottom edge")
        XCTAssertTrue(contains(240, 244), "top edge")
    }

    func testOnePointOutsideEachEdgeIsOutside() {
        XCTAssertFalse(contains(99, 222))
        XCTAssertFalse(contains(381, 222))
        XCTAssertFalse(contains(240, 199))
        XCTAssertFalse(contains(240, 245))
    }

    func testCornersOfTheBoundingBoxAreOutsideTheCapsule() {
        XCTAssertFalse(contains(101, 201))
        XCTAssertFalse(contains(379, 243))
        XCTAssertFalse(contains(101, 243))
        XCTAssertFalse(contains(379, 201))
    }

    func testRoundedRectangleCorners() {
        let rect = CGRect(x: 0, y: 0, width: 280, height: 64)
        func inside(_ x: CGFloat, _ y: CGFloat) -> Bool {
            HUDLayout.shape(rect, cornerRadius: 22, contains: CGPoint(x: x, y: y))
        }
        XCTAssertTrue(inside(0, 32), "straight part of the left edge")
        XCTAssertTrue(inside(7, 7), "on the corner arc")
        XCTAssertFalse(inside(5, 5), "outside the corner arc")
        XCTAssertFalse(inside(1, 1))
    }

    func testZeroRadiusIsAPlainRectangle() {
        XCTAssertTrue(contains(100, 200, radius: 0))
        XCTAssertTrue(contains(380, 244, radius: 0))
    }

    func testEmptyShapeContainsNothing() {
        XCTAssertFalse(HUDLayout.shape(.zero, cornerRadius: 0, contains: .zero))
    }
}
