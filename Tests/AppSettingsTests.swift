import XCTest
@testable import ModernMac

@MainActor
final class AppSettingsTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() async throws {
        // A suite of its own per test: nothing of the user's is read or written.
        suiteName = "com.ando.ModernMacTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    // MARK: - Defaults (SPEC §6)

    func testDefaultsOnACleanSlate() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.isEnabled)
        XCTAssertTrue(settings.handleVolume)
        XCTAssertTrue(settings.handleBrightness)
        XCTAssertEqual(settings.style, .tahoe)
        XCTAssertEqual(settings.position, .topRight)
        XCTAssertEqual(settings.hideDelay, 1.5)
        XCTAssertTrue(settings.isInteractive)
        XCTAssertFalse(settings.showPercentage)
        XCTAssertFalse(settings.showDeviceName)
        XCTAssertEqual(settings.playFeedbackSound, .followSystem)
        XCTAssertTrue(settings.showMenuBarIcon)
    }

    func testReadingDefaultsWritesNothing() {
        _ = AppSettings(defaults: defaults)
        XCTAssertNil(defaults.persistentDomain(forName: suiteName))
    }

    // MARK: - Persistence

    func testEverySettingSurvivesARoundTrip() {
        let settings = AppSettings(defaults: defaults)
        settings.isEnabled = false
        settings.handleVolume = false
        settings.handleBrightness = false
        settings.style = .circular
        settings.position = .bottomCenter
        settings.hideDelay = 2.4
        settings.isInteractive = false
        settings.showPercentage = true
        settings.showDeviceName = true
        settings.playFeedbackSound = .never
        settings.showMenuBarIcon = false

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertFalse(reloaded.isEnabled)
        XCTAssertFalse(reloaded.handleVolume)
        XCTAssertFalse(reloaded.handleBrightness)
        XCTAssertEqual(reloaded.style, .circular)
        XCTAssertEqual(reloaded.position, .bottomCenter)
        XCTAssertEqual(reloaded.hideDelay, 2.4)
        XCTAssertFalse(reloaded.isInteractive)
        XCTAssertTrue(reloaded.showPercentage)
        XCTAssertTrue(reloaded.showDeviceName)
        XCTAssertEqual(reloaded.playFeedbackSound, .never)
        XCTAssertFalse(reloaded.showMenuBarIcon)
    }

    func testValuesAreStoredUnderTheSpecKeys() {
        let settings = AppSettings(defaults: defaults)
        settings.isEnabled = false
        settings.handleVolume = false
        settings.handleBrightness = false
        settings.style = .notch
        settings.position = .topCenter
        settings.hideDelay = 0.9
        settings.isInteractive = false
        settings.showPercentage = true
        settings.showDeviceName = true
        settings.playFeedbackSound = .always
        settings.showMenuBarIcon = false

        XCTAssertEqual(defaults.object(forKey: "isEnabled") as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "handleVolume") as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "handleBrightness") as? Bool, false)
        XCTAssertEqual(defaults.string(forKey: "style"), "notch")
        XCTAssertEqual(defaults.string(forKey: "position"), "topCenter")
        XCTAssertEqual(defaults.object(forKey: "hideDelay") as? Double, 0.9)
        XCTAssertEqual(defaults.object(forKey: "isInteractive") as? Bool, false)
        XCTAssertEqual(defaults.object(forKey: "showPercentage") as? Bool, true)
        XCTAssertEqual(defaults.object(forKey: "showDeviceName") as? Bool, true)
        XCTAssertEqual(defaults.string(forKey: "playFeedbackSound"), "always")
        XCTAssertEqual(defaults.object(forKey: "showMenuBarIcon") as? Bool, false)
    }

    func testEachStyleAndPositionAndPolicyRoundTrips() {
        let settings = AppSettings(defaults: defaults)
        for style in HUDStyle.allCases {
            settings.style = style
            XCTAssertEqual(AppSettings(defaults: defaults).style, style)
        }
        for position in HUDPosition.allCases {
            settings.position = position
            XCTAssertEqual(AppSettings(defaults: defaults).position, position)
        }
        for policy in AppSettings.FeedbackSoundPolicy.allCases {
            settings.playFeedbackSound = policy
            XCTAssertEqual(AppSettings(defaults: defaults).playFeedbackSound, policy)
        }
    }

    func testUnreadableStoredValuesFallBackToTheDefaults() {
        defaults.set("hologram", forKey: "style")
        defaults.set("middle", forKey: "position")
        defaults.set("sometimes", forKey: "playFeedbackSound")
        defaults.set("fast", forKey: "hideDelay")
        defaults.set("yes please", forKey: "isEnabled")

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.style, .tahoe)
        XCTAssertEqual(settings.position, .topRight)
        XCTAssertEqual(settings.playFeedbackSound, .followSystem)
        XCTAssertEqual(settings.hideDelay, 1.5)
        XCTAssertTrue(settings.isEnabled)
    }

    func testSuitesAreIsolatedFromEachOther() {
        let otherName = "com.ando.ModernMacTests.\(UUID().uuidString)"
        let other = UserDefaults(suiteName: otherName)!
        defer { other.removePersistentDomain(forName: otherName) }

        AppSettings(defaults: defaults).style = .circular
        XCTAssertEqual(AppSettings(defaults: other).style, .tahoe)
    }

    // MARK: - Applied live

    func testAChangeShowsInTheOptionsAtOnce() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.hudOptions, HUDOptions())

        settings.style = .notch
        settings.position = .topLeft
        settings.isInteractive = false
        settings.showPercentage = true
        settings.showDeviceName = true
        XCTAssertEqual(
            settings.hudOptions,
            HUDOptions(
                style: .notch, position: .topLeft, isInteractive: false,
                showsPercentage: true, showsDeviceName: true))
    }

    func testHideDelayIsClampedToItsRange() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.clampedHideDelay, 1.5)
        settings.hideDelay = 0.2
        XCTAssertEqual(settings.clampedHideDelay, 0.8)
        settings.hideDelay = 9
        XCTAssertEqual(settings.clampedHideDelay, 3.0)
        settings.hideDelay = 2.2
        XCTAssertEqual(settings.clampedHideDelay, 2.2)
    }

    func testFeedbackSoundPolicy() {
        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.isFeedbackSoundEnabled(systemSetting: true))
        XCTAssertFalse(settings.isFeedbackSoundEnabled(systemSetting: false))
        settings.playFeedbackSound = .always
        XCTAssertTrue(settings.isFeedbackSoundEnabled(systemSetting: false))
        settings.playFeedbackSound = .never
        XCTAssertFalse(settings.isFeedbackSoundEnabled(systemSetting: true))
    }

    // MARK: - Key toggles reach the router

    private let volumeKeys: [MediaKey] = [.soundUp, .soundDown, .mute]
    private let brightnessKeys: [MediaKey] = [.brightnessUp, .brightnessDown]

    private func isConsumed(_ key: MediaKey, _ settings: AppSettings) -> Bool {
        KeyRouter.route(key: key, modifiers: [], options: settings.routingOptions) != .passThrough
    }

    func testWithDefaultsEveryKeyIsTakenOver() {
        let settings = AppSettings(defaults: defaults)
        for key in volumeKeys + brightnessKeys {
            XCTAssertTrue(isConsumed(key, settings), "\(key)")
        }
    }

    func testVolumeHandlingOffPassesVolumeKeysThrough() {
        let settings = AppSettings(defaults: defaults)
        settings.handleVolume = false
        for key in volumeKeys { XCTAssertFalse(isConsumed(key, settings), "\(key)") }
        for key in brightnessKeys { XCTAssertTrue(isConsumed(key, settings), "\(key)") }
        // Also with the modifiers the router otherwise takes.
        XCTAssertEqual(
            KeyRouter.route(
                key: .soundUp, modifiers: [.shift, .option], options: settings.routingOptions),
            .passThrough)
    }

    func testBrightnessHandlingOffPassesBrightnessKeysThrough() {
        let settings = AppSettings(defaults: defaults)
        settings.handleBrightness = false
        for key in brightnessKeys { XCTAssertFalse(isConsumed(key, settings), "\(key)") }
        for key in volumeKeys { XCTAssertTrue(isConsumed(key, settings), "\(key)") }
        XCTAssertEqual(
            KeyRouter.route(
                key: .brightnessDown, modifiers: [.shift, .option],
                options: settings.routingOptions),
            .passThrough)
    }

    func testDisabledPassesEveryKeyThrough() {
        let settings = AppSettings(defaults: defaults)
        settings.isEnabled = false
        for key in volumeKeys + brightnessKeys {
            XCTAssertFalse(isConsumed(key, settings), "\(key)")
        }
    }

    func testTurningAToggleBackOnTakesTheKeysAgainWithoutReloading() {
        let settings = AppSettings(defaults: defaults)
        settings.handleVolume = false
        XCTAssertFalse(isConsumed(.soundUp, settings))
        settings.handleVolume = true
        XCTAssertTrue(isConsumed(.soundUp, settings))
    }

    func testStoredTogglesAreAppliedAfterARelaunch() {
        AppSettings(defaults: defaults).handleBrightness = false
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertFalse(isConsumed(.brightnessUp, reloaded))
        XCTAssertTrue(isConsumed(.soundDown, reloaded))
    }

    // MARK: - Names in the UI

    func testStyleNamesFollowTheSpec() {
        XCTAssertEqual(HUDStyle.allCases.map(\.displayName), ["macOS 26", "Notch", "Circular"])
        XCTAssertFalse(HUDStyle.notch.usesPosition)
        XCTAssertTrue(HUDStyle.tahoe.usesPosition)
        XCTAssertTrue(HUDStyle.circular.usesPosition)
        XCTAssertEqual(HUDStyle.allCases.filter(\.showsDeviceName), [.tahoe])
    }

    // MARK: - Preview screen

    func testThePreviewScreenHasANotchOnlyForTheNotchStyle() {
        XCTAssertNotNil(NotchLayout.notchRect(in: HUDPreview.screen(for: .notch)))
        XCTAssertNil(NotchLayout.notchRect(in: HUDPreview.screen(for: .tahoe)))
        XCTAssertNil(NotchLayout.notchRect(in: HUDPreview.screen(for: .circular)))
        XCTAssertEqual(
            NotchLayout.notchRect(in: HUDPreview.screen(for: .notch))?.size, HUDPreview.notchSize)
    }

    func testEveryStyleFitsInsideThePreviewAtEveryPosition() {
        for style in HUDStyle.allCases {
            for position in HUDPosition.allCases {
                for named in [false, true] {
                    var options = HUDOptions()
                    options.style = style
                    options.position = position
                    options.showsDeviceName = named
                    let screen = HUDPreview.screen(for: style)
                    let shape = style.placement(
                        options: options, screen: screen, reduceMotion: false).hitFrame
                    XCTAssertTrue(
                        screen.frame.contains(shape), "\(style) \(position) named=\(named)")
                }
            }
        }
    }
}
