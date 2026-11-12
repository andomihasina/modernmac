import XCTest
@testable import ModernMac

@MainActor
final class LevelDragHandlerTests: XCTestCase {
    private var volume: FakeVolumeController!
    private var brightness: FakeBrightnessController!
    private var feedback: FakeFeedbackSound!
    private var scheduler: FakeScheduler!
    private var feedbackEnabled: Bool!
    private var presented: [HUDState]!
    private var handler: LevelDragHandler!

    private let interval = LevelDragHandler.minimumWriteInterval

    override func setUp() async throws {
        volume = FakeVolumeController(level: 0.5)
        brightness = FakeBrightnessController(level: 0.5)
        feedback = FakeFeedbackSound()
        scheduler = FakeScheduler()
        feedbackEnabled = true
        presented = []
        handler = LevelDragHandler(
            volume: volume,
            brightness: brightness,
            feedback: feedback,
            isFeedbackEnabled: { [unowned self] in self.feedbackEnabled },
            scheduler: scheduler,
            present: { [unowned self] in self.presented.append($0) })
    }

    // MARK: - Throttling

    func testFirstChangeIsWrittenAtOnce() {
        handler.begin(.volume)
        handler.change(to: 0.3)
        XCTAssertEqual(volume.setLevelCalls, [0.3])
    }

    func testChangesInsideTheIntervalAreHeldBack() {
        handler.begin(.volume)
        handler.change(to: 0.30)
        scheduler.advance(by: 0.004)
        handler.change(to: 0.31)
        scheduler.advance(by: 0.004)
        handler.change(to: 0.32)
        XCTAssertEqual(volume.setLevelCalls, [0.30])
    }

    func testTheNewestHeldLevelIsWrittenWhenTheIntervalIsOver() {
        handler.begin(.volume)
        handler.change(to: 0.30)
        scheduler.advance(by: 0.004)
        handler.change(to: 0.31)
        scheduler.advance(by: 0.004)
        handler.change(to: 0.32)
        // 8 ms in; the pointer stops. The write comes at 16 ms on its own.
        scheduler.advance(by: 0.007)
        XCTAssertEqual(volume.setLevelCalls, [0.30])
        scheduler.advance(by: 0.001)
        XCTAssertEqual(volume.setLevelCalls, [0.30, 0.32])
    }

    func testAChangeAfterTheIntervalIsWrittenAtOnce() {
        handler.begin(.volume)
        handler.change(to: 0.30)
        scheduler.advance(by: interval)
        handler.change(to: 0.40)
        XCTAssertEqual(volume.setLevelCalls, [0.30, 0.40])
        XCTAssertEqual(scheduler.pendingCount, 0)
    }

    func testAtMostOneWritePerIntervalDuringALongDrag() {
        handler.begin(.volume)
        // One second of pointer events, one per millisecond.
        var writeTimes: [TimeInterval] = []
        var seen = 0
        for step in 0..<1000 {
            handler.change(to: Double(step) / 1000)
            scheduler.advance(by: 0.001)
            if volume.setLevelCalls.count > seen {
                seen = volume.setLevelCalls.count
                writeTimes.append(scheduler.now)
            }
        }
        XCTAssertLessThanOrEqual(volume.setLevelCalls.count, 63)
        XCTAssertGreaterThanOrEqual(volume.setLevelCalls.count, 55)
        for (earlier, later) in zip(writeTimes, writeTimes.dropFirst()) {
            XCTAssertGreaterThanOrEqual(later - earlier, interval - 0.0011)
        }
    }

    func testOnlyOneTimerIsPendingAtATime() {
        handler.begin(.volume)
        handler.change(to: 0.30)
        for step in 1...5 {
            scheduler.advance(by: 0.002)
            handler.change(to: 0.30 + Double(step) / 100)
        }
        XCTAssertEqual(scheduler.pendingCount, 1)
    }

    func testEndWritesTheHeldLevel() {
        handler.begin(.volume)
        handler.change(to: 0.30)
        scheduler.advance(by: 0.002)
        handler.change(to: 0.45)
        handler.end()
        XCTAssertEqual(volume.setLevelCalls, [0.30, 0.45])
        XCTAssertEqual(scheduler.pendingCount, 0)
        // Nothing fires later.
        scheduler.advance(by: 1)
        XCTAssertEqual(volume.setLevelCalls, [0.30, 0.45])
    }

    func testANewDragWritesAtOnceAgain() {
        handler.begin(.volume)
        handler.change(to: 0.30)
        handler.end()
        scheduler.advance(by: 0.001)
        handler.begin(.volume)
        handler.change(to: 0.60)
        XCTAssertEqual(volume.setLevelCalls, [0.30, 0.60])
    }

    // MARK: - What is shown

    func testEveryChangeIsPresentedEvenWhenTheWriteIsHeld() {
        handler.begin(.volume)
        handler.change(to: 0.30)
        handler.change(to: 0.31)
        handler.change(to: 0.32)
        XCTAssertEqual(presented.map(\.level), [0.30, 0.31, 0.32])
        XCTAssertEqual(presented.map(\.kind), [.volume, .volume, .volume])
    }

    func testLevelIsContinuousAndClamped() {
        handler.begin(.volume)
        handler.change(to: 0.1234)
        scheduler.advance(by: interval)
        handler.change(to: 1.7)
        scheduler.advance(by: interval)
        handler.change(to: -0.2)
        XCTAssertEqual(volume.setLevelCalls, [0.1234, 1, 0])
    }

    func testEndPresentsWhatTheHardwareSettledOn() {
        handler.begin(.volume)
        handler.change(to: 0.30)
        volume.level = 0.3125  // the device rounds to its own steps
        handler.end()
        XCTAssertEqual(presented.last?.level, 0.3125)
    }

    func testIsActiveOnlyBetweenBeginAndEnd() {
        XCTAssertFalse(handler.isActive)
        handler.begin(.volume)
        XCTAssertTrue(handler.isActive)
        handler.end()
        XCTAssertFalse(handler.isActive)
    }

    // MARK: - Mute

    func testDraggingWhileMutedUnmutesOnce() {
        volume.isMuted = true
        handler.begin(.volume)
        handler.change(to: 0.30)
        scheduler.advance(by: interval)
        handler.change(to: 0.35)
        XCTAssertEqual(volume.setMutedCalls, [false])
        XCTAssertEqual(presented.first?.isMuted, false)
    }

    func testDraggingWhileNotMutedLeavesMuteAlone() {
        handler.begin(.volume)
        handler.change(to: 0.30)
        XCTAssertEqual(volume.setMutedCalls, [])
    }

    // MARK: - Feedback sound

    func testNoFeedbackDuringTheDragOneOnRelease() {
        handler.begin(.volume)
        handler.change(to: 0.30)
        scheduler.advance(by: interval)
        handler.change(to: 0.40)
        XCTAssertEqual(feedback.playCount, 0)
        handler.end()
        XCTAssertEqual(feedback.playCount, 1)
    }

    func testNoFeedbackOnReleaseWhenThePreferenceIsOff() {
        feedbackEnabled = false
        handler.begin(.volume)
        handler.change(to: 0.30)
        handler.end()
        XCTAssertEqual(feedback.playCount, 0)
    }

    func testNoFeedbackForAPressThatNeverMoved() {
        handler.begin(.volume)
        handler.end()
        XCTAssertEqual(feedback.playCount, 0)
        XCTAssertEqual(volume.setLevelCalls, [])
    }

    func testNoFeedbackForBrightness() {
        handler.begin(.brightness)
        handler.change(to: 0.30)
        handler.end()
        XCTAssertEqual(feedback.playCount, 0)
    }

    // MARK: - Brightness

    func testBrightnessDragWritesToTheDisplayThatWasRead() {
        brightness.displayID = 42
        handler.begin(.brightness)
        handler.change(to: 0.8)
        XCTAssertEqual(brightness.setLevelCalls.map(\.level), [0.8])
        XCTAssertEqual(brightness.setLevelCalls.map(\.displayID), [42])
        XCTAssertEqual(presented.first?.kind, .brightness)
        XCTAssertEqual(volume.setLevelCalls, [])
    }

    // MARK: - Hardware trouble

    func testBeginFailsWhenVolumeCannotBeRead() {
        volume.readError = .notSettable
        XCTAssertFalse(handler.begin(.volume))
        handler.change(to: 0.3)
        handler.end()
        XCTAssertEqual(volume.setLevelCalls, [])
        XCTAssertTrue(presented.isEmpty)
        XCTAssertEqual(feedback.playCount, 0)
    }

    func testBeginFailsWhenBrightnessIsUnavailable() {
        brightness.isAvailable = false
        XCTAssertFalse(handler.begin(.brightness))
        handler.change(to: 0.3)
        XCTAssertTrue(brightness.setLevelCalls.isEmpty)
    }

    func testAFailedWriteDoesNotStopTheDrag() {
        handler.begin(.volume)
        volume.setLevelError = .failed(status: -1)
        handler.change(to: 0.30)
        volume.setLevelError = nil
        scheduler.advance(by: interval)
        handler.change(to: 0.40)
        XCTAssertEqual(volume.setLevelCalls, [0.40])
    }

    func testChangeWithoutBeginDoesNothing() {
        handler.change(to: 0.3)
        XCTAssertEqual(volume.setLevelCalls, [])
        XCTAssertTrue(presented.isEmpty)
    }
}
