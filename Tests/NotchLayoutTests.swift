import XCTest
@testable import ModernMac

@MainActor
final class NotchLayoutTests: XCTestCase {
    // MARK: - Fake screens

    /// Measured on Ando's MacBook Air (FINDINGS V6): the notch is one point
    /// off-centre, 646 to its left and 645 to its right.
    private let air = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 1470, height: 956),
        visibleFrame: CGRect(x: 0, y: 58, width: 1470, height: 861),
        safeAreaTop: 32,
        auxiliaryTopLeftWidth: 646,
        auxiliaryTopRightWidth: 645)

    /// A 14-inch layout. The numbers are representative, not measured.
    private let fourteenInch = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944),
        safeAreaTop: 38,
        auxiliaryTopLeftWidth: 664,
        auxiliaryTopRightWidth: 663)

    /// A 16-inch layout, placed to the right of another display and lower.
    /// Representative, not measured.
    private let sixteenInch = ScreenMetrics(
        frame: CGRect(x: 1920, y: -37, width: 1728, height: 1117),
        visibleFrame: CGRect(x: 1920, y: 40, width: 1728, height: 1040),
        safeAreaTop: 37,
        auxiliaryTopLeftWidth: 771,
        auxiliaryTopRightWidth: 771)

    /// An external display with a menu bar and no notch.
    private let external = ScreenMetrics(
        frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1055))

    /// An external display that is not the menu bar screen.
    private let bareExternal = ScreenMetrics(
        frame: CGRect(x: 1470, y: -124, width: 2560, height: 1440),
        visibleFrame: CGRect(x: 1470, y: -124, width: 2560, height: 1440))

    // MARK: - Notch rectangle

    func testNotchOnTheMeasuredMacBookAir() {
        // FINDINGS V6: 179 × 32 spanning x 646…825, flush with the top.
        XCTAssertEqual(
            NotchLayout.notchRect(in: air), CGRect(x: 646, y: 924, width: 179, height: 32))
    }

    func testNotchOnAFourteenInchLayout() {
        XCTAssertEqual(
            NotchLayout.notchRect(in: fourteenInch), CGRect(x: 664, y: 944, width: 185, height: 38))
    }

    func testNotchOnASixteenInchLayoutAwayFromTheOrigin() {
        // x = 1920 + 771; top edge = −37 + 1117 = 1080.
        XCTAssertEqual(
            NotchLayout.notchRect(in: sixteenInch),
            CGRect(x: 2691, y: 1043, width: 186, height: 37))
    }

    func testNotchIsFlushWithTheTopOfItsScreen() {
        for screen in [air, fourteenInch, sixteenInch] {
            XCTAssertEqual(NotchLayout.notchRect(in: screen)?.maxY, screen.frame.maxY)
        }
    }

    func testExternalDisplayHasNoNotch() {
        XCTAssertNil(NotchLayout.notchRect(in: external))
        XCTAssertNil(NotchLayout.notchRect(in: bareExternal))
    }

    func testNoNotchWithoutAuxiliaryAreas() {
        // A safe area alone does not say where the notch is.
        var screen = air
        screen.auxiliaryTopLeftWidth = nil
        XCTAssertNil(NotchLayout.notchRect(in: screen))
        screen = air
        screen.auxiliaryTopRightWidth = nil
        XCTAssertNil(NotchLayout.notchRect(in: screen))
    }

    func testNoNotchWhenTheAuxiliaryAreasLeaveNoRoom() {
        var screen = air
        screen.auxiliaryTopLeftWidth = 735
        screen.auxiliaryTopRightWidth = 735
        XCTAssertNil(NotchLayout.notchRect(in: screen))
    }

    func testNoNotchWithoutASafeArea() {
        var screen = air
        screen.safeAreaTop = 0
        XCTAssertNil(NotchLayout.notchRect(in: screen))
    }

    // MARK: - Fallback selection

    func testNotchedScreensUseTheNotch() {
        XCTAssertEqual(
            NotchLayout.mode(for: air), .notch(CGRect(x: 646, y: 924, width: 179, height: 32)))
        XCTAssertNotEqual(NotchLayout.mode(for: fourteenInch), .pill)
        XCTAssertNotEqual(NotchLayout.mode(for: sixteenInch), .pill)
    }

    func testScreensWithoutANotchUseThePill() {
        XCTAssertEqual(NotchLayout.mode(for: external), .pill)
        XCTAssertEqual(NotchLayout.mode(for: bareExternal), .pill)
    }

    // MARK: - Expanded shape

    func testExpandedGrowsDownwardAtTheSameWidth() {
        let notch = CGRect(x: 646, y: 924, width: 179, height: 32)
        XCTAssertEqual(
            NotchLayout.expandedRect(notch: notch, dropHeight: 34),
            CGRect(x: 646, y: 890, width: 179, height: 66))
    }

    func testExpandedKeepsTheNotchSidesAndTheTopEdge() {
        for screen in [air, fourteenInch, sixteenInch] {
            let notch = NotchLayout.notchRect(in: screen)!
            let expanded = NotchLayout.expandedRect(notch: notch, dropHeight: 34)
            XCTAssertEqual(expanded.minX, notch.minX)
            XCTAssertEqual(expanded.maxX, notch.maxX)
            XCTAssertEqual(expanded.maxY, screen.frame.maxY)
            XCTAssertEqual(expanded.height, notch.height + 34)
            XCTAssertTrue(expanded.contains(notch))
        }
    }

    func testZeroDropIsTheNotchItself() {
        let notch = CGRect(x: 646, y: 924, width: 179, height: 32)
        XCTAssertEqual(NotchLayout.expandedRect(notch: notch, dropHeight: 0), notch)
    }

    func testPanelHangsFromTheTopOfTheScreen() {
        let expanded = CGRect(x: 646, y: 890, width: 179, height: 66)
        let panel = NotchLayout.panelFrame(expanded: expanded, sidePadding: 24, bottomPadding: 24)
        XCTAssertEqual(panel, CGRect(x: 622, y: 866, width: 227, height: 90))
        XCTAssertEqual(panel.maxY, air.frame.maxY)
        XCTAssertEqual(panel.midX, expanded.midX)
    }

    // MARK: - Pill

    func testPillIsCentredBelowTheMenuBar() {
        let pill = NotchLayout.pillRect(
            size: CGSize(width: 316, height: 32), screen: external, topMargin: 8)
        // 8 below visibleFrame.maxY (1055).
        XCTAssertEqual(pill, CGRect(x: 802, y: 1015, width: 316, height: 32))
    }

    func testPillOnAScreenWithoutAMenuBar() {
        let pill = NotchLayout.pillRect(
            size: CGSize(width: 316, height: 32), screen: bareExternal, topMargin: 8)
        // Centre x = 1470 + 1280; top edge = −124 + 1440 = 1316.
        XCTAssertEqual(pill, CGRect(x: 2592, y: 1276, width: 316, height: 32))
    }

    // MARK: - Placement of the style

    private var options: HUDOptions {
        var options = HUDOptions()
        options.style = .notch
        return options
    }

    func testPlacementAtTheNotch() {
        let placement = HUDStyle.notch.placement(options: options, screen: air, reduceMotion: false)
        let drop = NotchHUDView.dropHeight
        let expanded = CGRect(x: 646, y: 924 - drop, width: 179, height: 32 + drop)

        XCTAssertEqual(placement.hitFrame, expanded)
        XCTAssertEqual(placement.hoverHitFrame, expanded)
        XCTAssertTrue(placement.isOverMenuBar)
        XCTAssertEqual(placement.panelFrame.maxY, 956, "flush with the top of the screen")
        XCTAssertTrue(placement.panelFrame.contains(expanded))
        // Grows out of the notch: no fade.
        XCTAssertEqual(placement.motion.appearFade, 0)
        XCTAssertEqual(placement.motion.disappearFade, 0)
        XCTAssertGreaterThan(placement.motion.orderOutDelay, 0)
    }

    func testTheShapeNeverCoversTheMenuBarBesideTheNotch() {
        for screen in [air, fourteenInch, sixteenInch] {
            let notch = NotchLayout.notchRect(in: screen)!
            let placement = HUDStyle.notch.placement(
                options: options, screen: screen, reduceMotion: false)
            XCTAssertEqual(placement.hitFrame.minX, notch.minX)
            XCTAssertEqual(placement.hitFrame.maxX, notch.maxX)
        }
    }

    func testPlacementAsAPillOnAnExternalDisplay() {
        let placement = HUDStyle.notch.placement(
            options: options, screen: external, reduceMotion: false)
        let pill = NotchLayout.pillRect(
            size: NotchHUDView.pillSize, screen: external, topMargin: NotchHUDView.pillTopMargin)

        XCTAssertEqual(placement.hitFrame, pill)
        XCTAssertEqual(placement.hoverHitFrame, pill)
        XCTAssertEqual(placement.hitCornerRadius, NotchHUDView.pillSize.height / 2)
        XCTAssertFalse(placement.isOverMenuBar)
        XCTAssertLessThanOrEqual(pill.maxY, external.visibleFrame.maxY, "below the menu bar")
        XCTAssertGreaterThan(placement.motion.appearFade, 0)
    }

    func testReduceMotionFadesInsteadOfGrowing() {
        let placement = HUDStyle.notch.placement(options: options, screen: air, reduceMotion: true)
        XCTAssertGreaterThan(placement.motion.appearFade, 0)
        XCTAssertGreaterThan(placement.motion.disappearFade, 0)
    }

    func testTahoePlacementIsUnchangedByTheNotch() {
        var tahoe = HUDOptions()
        tahoe.style = .tahoe
        let placement = HUDStyle.tahoe.placement(options: tahoe, screen: air, reduceMotion: false)
        XCTAssertEqual(placement.hitFrame, CGRect(x: 1180, y: 865, width: 280, height: 44))
        XCTAssertEqual(placement.hoverHitFrame, placement.hitFrame)
        XCTAssertFalse(placement.isOverMenuBar)
    }
}
