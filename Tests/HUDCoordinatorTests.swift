import XCTest
@testable import ModernMac

@MainActor
final class HUDCoordinatorTests: XCTestCase {
    private var scheduler: FakeScheduler!
    private var hideDelay: TimeInterval!
    private var coordinator: HUDCoordinator!
    private var changes: [HUDPresentation]!

    override func setUp() async throws {
        scheduler = FakeScheduler()
        hideDelay = 1.5
        changes = []
        coordinator = HUDCoordinator(scheduler: scheduler, hideDelay: { [unowned self] in self.hideDelay })
        coordinator.onChange = { [unowned self] in self.changes.append($0) }
    }

    private func volume(_ level: Double, muted: Bool = false) -> HUDState {
        .volume(VolumeReading(level: level, isMuted: muted, deviceName: "Speakers"))
    }

    private func brightness(_ level: Double) -> HUDState {
        .brightness(BrightnessReading(level: level, displayID: 1, displayName: "Display"))
    }

    private var isVisible: Bool { coordinator.presentation.isVisible }

    // MARK: - Show and hide

    func testStartsHidden() {
        XCTAssertFalse(isVisible)
        XCTAssertNil(coordinator.presentation.state)
    }

    func testShowMakesItVisibleWithTheState() {
        coordinator.show(volume(0.5))
        XCTAssertTrue(isVisible)
        XCTAssertEqual(coordinator.presentation.state, volume(0.5))
        XCTAssertEqual(changes.count, 1)
    }

    func testHidesAfterTheDelay() {
        coordinator.show(volume(0.5))
        scheduler.advance(by: 1.49)
        XCTAssertTrue(isVisible)
        scheduler.advance(by: 0.01)
        XCTAssertFalse(isVisible)
    }

    func testKeepsTheLastStateAfterHiding() {
        coordinator.show(volume(0.5))
        scheduler.advance(by: 2)
        XCTAssertFalse(isVisible)
        XCTAssertEqual(coordinator.presentation.state, volume(0.5))
    }

    func testUsesTheCurrentHideDelaySetting() {
        hideDelay = 3.0
        coordinator.show(volume(0.5))
        scheduler.advance(by: 2.9)
        XCTAssertTrue(isVisible)
        scheduler.advance(by: 0.1)
        XCTAssertFalse(isVisible)
    }

    func testANewEventRestartsTheTimer() {
        coordinator.show(volume(0.5))
        scheduler.advance(by: 1.0)
        coordinator.show(volume(0.5625))
        scheduler.advance(by: 1.0)
        XCTAssertTrue(isVisible, "2.0 s after the first event, 1.0 s after the second")
        scheduler.advance(by: 0.5)
        XCTAssertFalse(isVisible)
    }

    func testHeldKeyKeepsItOpenWithOnePendingTimer() {
        for step in 0..<40 {
            coordinator.show(volume(Double(step) / 64))
            scheduler.advance(by: 0.1)
            XCTAssertTrue(isVisible)
            XCTAssertEqual(scheduler.pendingCount, 1)
        }
        scheduler.advance(by: 1.5)
        XCTAssertFalse(isVisible)
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    func testCanShowAgainAfterHiding() {
        coordinator.show(volume(0.5))
        scheduler.advance(by: 2)
        coordinator.show(volume(0.25))
        XCTAssertTrue(isVisible)
        scheduler.advance(by: 1.5)
        XCTAssertFalse(isVisible)
    }

    func testHideNowCancelsTheTimer() {
        coordinator.show(volume(0.5))
        coordinator.hide()
        XCTAssertFalse(isVisible)
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    // MARK: - Kind swap

    func testADifferentKindSwapsInPlace() {
        coordinator.show(volume(0.5))
        scheduler.advance(by: 1.0)
        coordinator.show(brightness(0.75), displayID: 1)

        XCTAssertEqual(coordinator.presentation.state?.kind, .brightness)
        XCTAssertEqual(coordinator.presentation.displayID, 1)
        XCTAssertEqual(changes.map(\.isVisible), [true, true], "never hidden in between")

        scheduler.advance(by: 1.0)
        XCTAssertTrue(isVisible, "the swap restarted the timer")
        scheduler.advance(by: 0.5)
        XCTAssertFalse(isVisible)
    }

    func testAlternatingKindsNeverHides() {
        for index in 0..<10 {
            coordinator.show(index.isMultiple(of: 2) ? volume(0.5) : brightness(0.5))
            scheduler.advance(by: 0.3)
        }
        XCTAssertTrue(changes.allSatisfy(\.isVisible))
    }

    // MARK: - External changes

    func testUpdateRefreshesAVisibleHUDOfTheSameKind() {
        coordinator.show(volume(0.5))
        coordinator.update(volume(0.75))
        XCTAssertEqual(coordinator.presentation.state?.level, 0.75)
    }

    func testUpdateDoesNotOpenAHiddenHUD() {
        coordinator.update(volume(0.75))
        XCTAssertFalse(isVisible)
        XCTAssertTrue(changes.isEmpty)
    }

    func testUpdateDoesNotReopenAfterHiding() {
        coordinator.show(volume(0.5))
        scheduler.advance(by: 2)
        coordinator.update(volume(0.75))
        XCTAssertFalse(isVisible)
        XCTAssertEqual(coordinator.presentation.state?.level, 0.5)
    }

    func testUpdateOfAnotherKindIsIgnored() {
        coordinator.show(brightness(0.5))
        coordinator.update(volume(0.75))
        XCTAssertEqual(coordinator.presentation.state, brightness(0.5))
    }

    func testUpdateDoesNotExtendTheTimeOnScreen() {
        coordinator.show(volume(0.5))
        scheduler.advance(by: 1.0)
        coordinator.update(volume(0.75))
        scheduler.advance(by: 0.5)
        XCTAssertFalse(isVisible)
    }

    func testIdenticalStateDoesNotNotifyAgain() {
        coordinator.show(volume(0.5))
        coordinator.update(volume(0.5))
        XCTAssertEqual(changes.count, 1)
    }

    // MARK: - Hover

    func testHoverHoldsItOpen() {
        coordinator.show(volume(0.5))
        scheduler.advance(by: 1.0)
        coordinator.setHovering(true)
        scheduler.advance(by: 60)
        XCTAssertTrue(isVisible)
    }

    func testLeavingRestartsTheFullDelay() {
        coordinator.show(volume(0.5))
        coordinator.setHovering(true)
        scheduler.advance(by: 10)
        coordinator.setHovering(false)
        scheduler.advance(by: 1.49)
        XCTAssertTrue(isVisible)
        scheduler.advance(by: 0.01)
        XCTAssertFalse(isVisible)
    }

    func testKeyEventsWhileHoveringUpdateWithoutStartingATimer() {
        coordinator.show(volume(0.5))
        coordinator.setHovering(true)
        coordinator.show(volume(0.5625))
        XCTAssertEqual(coordinator.presentation.state?.level, 0.5625)
        XCTAssertEqual(scheduler.pendingCount, 0)
        scheduler.advance(by: 60)
        XCTAssertTrue(isVisible)
    }

    func testHoverWhileHiddenDoesNotShowAnything() {
        coordinator.setHovering(true)
        coordinator.setHovering(false)
        scheduler.advance(by: 5)
        XCTAssertFalse(isVisible)
        XCTAssertTrue(changes.isEmpty)
    }

    // MARK: - Drag

    func testDragHoldsItOpen() {
        coordinator.show(volume(0.5))
        coordinator.beginDrag()
        scheduler.advance(by: 60)
        XCTAssertTrue(isVisible)
    }

    func testDragReleasedOutsideHidesAfterTheReleaseDelay() {
        coordinator.show(volume(0.5))
        coordinator.setHovering(true)
        coordinator.beginDrag()
        coordinator.setHovering(false)   // pointer left while dragging
        scheduler.advance(by: 30)
        XCTAssertTrue(isVisible, "still dragging")

        coordinator.endDrag()
        scheduler.advance(by: 0.79)
        XCTAssertTrue(isVisible)
        scheduler.advance(by: 0.01)
        XCTAssertFalse(isVisible)
    }

    func testDragReleasedInsideStaysWhileHovering() {
        coordinator.show(volume(0.5))
        coordinator.setHovering(true)
        coordinator.beginDrag()
        coordinator.endDrag()
        scheduler.advance(by: 60)
        XCTAssertTrue(isVisible, "the pointer is still over the HUD")

        coordinator.setHovering(false)
        scheduler.advance(by: 1.5)
        XCTAssertFalse(isVisible)
    }

    func testLevelChangesDuringADragKeepItOpen() {
        coordinator.show(volume(0.5))
        coordinator.beginDrag()
        for step in 0..<20 {
            coordinator.show(volume(Double(step) / 20))
            scheduler.advance(by: 0.5)
        }
        XCTAssertTrue(isVisible)
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    func testEndDragWithoutBeginDoesNothing() {
        coordinator.show(volume(0.5))
        coordinator.endDrag()
        scheduler.advance(by: 1.0)
        XCTAssertTrue(isVisible, "the normal 1.5 s timer still applies")
        scheduler.advance(by: 0.5)
        XCTAssertFalse(isVisible)
    }

    func testHidingClearsHoverAndDragHolds() {
        coordinator.show(volume(0.5))
        coordinator.setHovering(true)
        coordinator.beginDrag()
        coordinator.hide()

        coordinator.show(volume(0.5))
        scheduler.advance(by: 1.5)
        XCTAssertFalse(isVisible, "stale holds must not pin the next HUD open")
    }
}
