import XCTest
@testable import ModernMac

/// The key path end to end with fake hardware: what gets applied, what the HUD
/// is told, and above all when the event is left for macOS (fail open).
@MainActor
final class KeyEventHandlerTests: XCTestCase {
    private var volume: FakeVolumeController!
    private var brightness: FakeBrightnessController!
    private var feedback: FakeFeedbackSound!
    private var options: RoutingOptions!
    private var feedbackEnabled: Bool!
    private var presented: [(state: HUDState, displayID: UInt32?)]!
    private var handler: KeyEventHandler!

    override func setUp() async throws {
        volume = FakeVolumeController(level: 0.5)
        brightness = FakeBrightnessController(level: 0.5)
        feedback = FakeFeedbackSound()
        options = RoutingOptions()
        feedbackEnabled = false
        presented = []
        handler = KeyEventHandler(
            volume: volume,
            brightness: brightness,
            feedback: feedback,
            options: { [unowned self] in self.options },
            isFeedbackEnabled: { [unowned self] in self.feedbackEnabled },
            present: { [unowned self] state, displayID in self.presented.append((state, displayID)) })
    }

    private func down(
        _ key: MediaKey, _ modifiers: KeyModifiers = [], isRepeat: Bool = false
    ) -> Bool {
        handler.handle(MediaKeyEvent(key: key, isDown: true, isRepeat: isRepeat, modifiers: modifiers))
    }

    private func up(_ key: MediaKey, _ modifiers: KeyModifiers = []) -> Bool {
        handler.handle(MediaKeyEvent(key: key, isDown: false, modifiers: modifiers))
    }

    // MARK: - Volume

    func testVolumeUpStepsAndShowsTheHUD() {
        XCTAssertTrue(down(.soundUp))
        XCTAssertEqual(volume.level, 9.0 / 16)
        XCTAssertEqual(presented.count, 1)
        XCTAssertEqual(presented[0].state.kind, .volume)
        XCTAssertEqual(presented[0].state.level, 9.0 / 16)
        XCTAssertEqual(presented[0].state.isMuted, false)
        XCTAssertEqual(presented[0].state.deviceName, "Fake Speakers")
        XCTAssertEqual(presented[0].state.symbolName, HUDState.speakerSymbol)
        XCTAssertNil(presented[0].displayID)
    }

    func testVolumeDownSteps() {
        XCTAssertTrue(down(.soundDown))
        XCTAssertEqual(volume.level, 7.0 / 16)
    }

    func testFineVolumeStep() {
        XCTAssertTrue(down(.soundUp, [.shift, .option]))
        XCTAssertEqual(volume.level, 33.0 / 64)
    }

    func testKeyRepeatCountsAsAnotherStep() {
        XCTAssertTrue(down(.soundUp))
        XCTAssertTrue(down(.soundUp, isRepeat: true))
        XCTAssertTrue(down(.soundUp, isRepeat: true))
        XCTAssertEqual(volume.level, 11.0 / 16)
        XCTAssertEqual(presented.count, 3)
    }

    func testVolumeUpWhileMutedUnmutesAndSteps() {
        volume.isMuted = true
        XCTAssertTrue(down(.soundUp))
        XCTAssertFalse(volume.isMuted)
        XCTAssertEqual(volume.level, 9.0 / 16)
        XCTAssertEqual(presented.last?.state.isMuted, false)
    }

    func testVolumeDownWhileMutedUnmutesAndSteps() {
        volume.isMuted = true
        XCTAssertTrue(down(.soundDown))
        XCTAssertFalse(volume.isMuted)
        XCTAssertEqual(volume.level, 7.0 / 16)
        XCTAssertEqual(presented.last?.state.isMuted, false)
    }

    func testFailedUnmuteStillCountsAsHandledAndShowsMuted() {
        volume.isMuted = true
        volume.setMutedError = .notSettable
        XCTAssertTrue(down(.soundUp), "the level changed, so macOS must not step again")
        XCTAssertEqual(volume.level, 9.0 / 16)
        XCTAssertEqual(presented.last?.state.isMuted, true)
        XCTAssertEqual(presented.last?.state.symbolName, HUDState.mutedSymbol)
    }

    func testVolumeAtZeroShowsTheMutedSymbol() {
        volume.level = 1.0 / 16
        XCTAssertTrue(down(.soundDown))
        XCTAssertEqual(presented.last?.state.level, 0)
        XCTAssertEqual(presented.last?.state.symbolName, HUDState.mutedSymbol)
    }

    func testVolumeAtTheTopStillShowsTheHUD() {
        volume.level = 1
        XCTAssertTrue(down(.soundUp))
        XCTAssertEqual(volume.level, 1)
        XCTAssertEqual(presented.count, 1)
    }

    // MARK: - Mute

    func testMuteToggles() {
        XCTAssertTrue(down(.mute))
        XCTAssertTrue(volume.isMuted)
        XCTAssertEqual(presented.last?.state.isMuted, true)
        XCTAssertEqual(presented.last?.state.level, 0.5, "muting keeps the level")
        XCTAssertTrue(up(.mute))

        XCTAssertTrue(down(.mute, [.shift]))
        XCTAssertFalse(volume.isMuted)
        XCTAssertEqual(presented.last?.state.isMuted, false)
    }

    // MARK: - Feedback sound

    func testFeedbackPlaysOnEveryStepIncludingRepeats() {
        feedbackEnabled = true
        _ = down(.soundUp)
        _ = down(.soundUp, isRepeat: true)
        _ = down(.soundUp, isRepeat: true)
        XCTAssertEqual(feedback.playCount, 3)
    }

    func testFeedbackDoesNotPlayOnKeyUp() {
        feedbackEnabled = true
        _ = down(.soundUp)
        _ = up(.soundUp)
        XCTAssertEqual(feedback.playCount, 1)
    }

    func testFeedbackStaysSilentWhenThePreferenceIsOff() {
        _ = down(.soundUp)
        _ = down(.soundDown)
        XCTAssertEqual(feedback.playCount, 0)
    }

    func testShiftInvertsThePreference() {
        feedbackEnabled = false
        _ = down(.soundUp, [.shift])
        XCTAssertEqual(feedback.playCount, 1, "off + shift plays")

        feedbackEnabled = true
        _ = down(.soundUp, [.shift])
        XCTAssertEqual(feedback.playCount, 1, "on + shift is silent")
    }

    func testMuteAndBrightnessNeverPlayFeedback() {
        feedbackEnabled = true
        _ = down(.mute)
        _ = down(.brightnessUp)
        XCTAssertEqual(feedback.playCount, 0)
    }

    // MARK: - Brightness

    func testBrightnessStepsOnTheDisplayThatWasRead() {
        XCTAssertTrue(down(.brightnessUp))
        XCTAssertEqual(brightness.level, 9.0 / 16)
        XCTAssertEqual(brightness.setLevelCalls.last?.displayID, 7)
        XCTAssertEqual(presented.last?.state.kind, .brightness)
        XCTAssertEqual(presented.last?.state.level, 9.0 / 16)
        XCTAssertEqual(presented.last?.state.deviceName, "Fake Display")
        XCTAssertEqual(presented.last?.displayID, 7)

        XCTAssertTrue(down(.brightnessDown, [.shift, .option]))
        XCTAssertEqual(brightness.level, 35.0 / 64)
    }

    // MARK: - Key-up follows key-down

    func testKeyUpOfAConsumedKeyIsConsumed() {
        XCTAssertTrue(down(.soundUp))
        XCTAssertTrue(up(.soundUp))
    }

    func testKeyUpAfterRepeatsIsConsumedOnce() {
        XCTAssertTrue(down(.soundUp))
        XCTAssertTrue(down(.soundUp, isRepeat: true))
        XCTAssertTrue(up(.soundUp))
        XCTAssertFalse(up(.soundUp), "a second key-up belongs to nobody")
    }

    func testKeyUpOfAPassedThroughKeyPassesThrough() {
        XCTAssertFalse(down(.soundUp, [.option]))
        XCTAssertFalse(up(.soundUp, [.option]))
        XCTAssertFalse(down(.play))
        XCTAssertFalse(up(.play))
    }

    func testKeyUpIsConsumedEvenIfModifiersOrSettingsChangedMeanwhile() {
        XCTAssertTrue(down(.soundUp))
        options.isEnabled = false
        XCTAssertTrue(up(.soundUp, [.option]), "macOS never saw the key-down")
    }

    func testAStaleConsumedKeyDoesNotSwallowALaterPassedThroughPress() {
        XCTAssertTrue(down(.soundUp))   // its key-up is lost
        options.isEnabled = false
        XCTAssertFalse(down(.soundUp))
        XCTAssertFalse(up(.soundUp))
    }

    func testResetForgetsHalfFinishedPresses() {
        XCTAssertTrue(down(.soundUp))
        handler.reset()
        XCTAssertFalse(up(.soundUp))
    }

    func testKeysAreTrackedIndependently() {
        XCTAssertTrue(down(.soundUp))
        XCTAssertFalse(down(.brightnessUp, [.option]))
        XCTAssertFalse(up(.brightnessUp))
        XCTAssertTrue(up(.soundUp))
    }

    // MARK: - Fail open

    private func assertPassesThroughUntouched(
        _ key: MediaKey, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertFalse(down(key), "key-down must pass through", file: file, line: line)
        XCTAssertFalse(up(key), "key-up must pass through", file: file, line: line)
        XCTAssertTrue(presented.isEmpty, "no HUD for a key macOS handles", file: file, line: line)
        XCTAssertEqual(feedback.playCount, 0, file: file, line: line)
    }

    func testNoSettableVolumePassesThrough() {
        feedbackEnabled = true
        volume.readError = .notSettable
        assertPassesThroughUntouched(.soundUp)
        assertPassesThroughUntouched(.soundDown)
        assertPassesThroughUntouched(.mute)
        XCTAssertTrue(volume.setLevelCalls.isEmpty)
    }

    func testNoOutputDevicePassesThrough() {
        volume.readError = .noDevice
        assertPassesThroughUntouched(.soundUp)
        assertPassesThroughUntouched(.mute)
    }

    func testVolumeSetErrorPassesThrough() {
        feedbackEnabled = true
        volume.setLevelError = .failed(status: -1)
        assertPassesThroughUntouched(.soundUp)
        XCTAssertEqual(volume.level, 0.5)
    }

    func testMuteSetErrorPassesThrough() {
        volume.setMutedError = .notSettable
        assertPassesThroughUntouched(.mute)
        XCTAssertFalse(volume.isMuted)
    }

    func testBrightnessUnavailablePassesThrough() {
        brightness.isAvailable = false
        assertPassesThroughUntouched(.brightnessUp)
        assertPassesThroughUntouched(.brightnessDown)
        XCTAssertTrue(brightness.setLevelCalls.isEmpty)
    }

    func testNoAdjustableDisplayPassesThrough() {
        brightness.readError = .noDevice
        assertPassesThroughUntouched(.brightnessUp)
    }

    func testBrightnessSetErrorPassesThrough() {
        brightness.setLevelError = .failed(status: -1)
        assertPassesThroughUntouched(.brightnessDown)
        XCTAssertEqual(brightness.level, 0.5)
    }

    func testAppDisabledPassesEverythingThrough() {
        options.isEnabled = false
        for key in [MediaKey.soundUp, .soundDown, .mute, .brightnessUp, .brightnessDown] {
            assertPassesThroughUntouched(key)
        }
        XCTAssertEqual(volume.level, 0.5)
        XCTAssertEqual(brightness.level, 0.5)
    }

    func testVolumeHandlingOffPassesVolumeKeysOnly() {
        options.handleVolume = false
        assertPassesThroughUntouched(.soundUp)
        assertPassesThroughUntouched(.mute)
        XCTAssertTrue(down(.brightnessUp))
    }

    func testBrightnessHandlingOffPassesBrightnessKeysOnly() {
        options.handleBrightness = false
        assertPassesThroughUntouched(.brightnessUp)
        XCTAssertTrue(down(.soundUp))
    }

    func testTogglesApplyOnTheNextPressWithoutRestart() {
        XCTAssertTrue(down(.soundUp))
        XCTAssertTrue(up(.soundUp))
        options.isEnabled = false
        XCTAssertFalse(down(.soundUp))
        XCTAssertFalse(up(.soundUp))
        options.isEnabled = true
        XCTAssertTrue(down(.soundUp))
    }

    func testAFailureDoesNotStickOnceTheHardwareRecovers() {
        volume.readError = .noDevice
        XCTAssertFalse(down(.soundUp))
        XCTAssertFalse(up(.soundUp))
        volume.readError = nil
        XCTAssertTrue(down(.soundUp))
        XCTAssertTrue(up(.soundUp))
    }

    func testKeysWeDoNotHandleNeverTouchHardware() {
        for key in [MediaKey.play, .next, .previous, .illuminationUp, .illuminationDown, .illuminationToggle] {
            assertPassesThroughUntouched(key)
        }
        XCTAssertTrue(volume.setLevelCalls.isEmpty)
        XCTAssertTrue(brightness.setLevelCalls.isEmpty)
    }
}
