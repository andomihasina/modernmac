import XCTest
@testable import ModernMac

/// One test per row of the routing table in SPEC §4.2, plus the gaps between rows.
final class KeyRouterTests: XCTestCase {
    private func route(
        _ key: MediaKey, _ modifiers: KeyModifiers = [], options: RoutingOptions = RoutingOptions()
    ) -> KeyDecision {
        KeyRouter.route(key: key, modifiers: modifiers, options: options)
    }

    private let volumeKeys: [(key: MediaKey, direction: StepDirection)] = [
        (.soundUp, .up), (.soundDown, .down),
    ]
    private let brightnessKeys: [(key: MediaKey, direction: StepDirection)] = [
        (.brightnessUp, .up), (.brightnessDown, .down),
    ]

    // MARK: - Volume

    func testVolumeWithoutModifiersIsANormalStep() {
        for (key, direction) in volumeKeys {
            XCTAssertEqual(route(key), .consume(.volumeStep(direction, .normal, invertFeedback: false)))
        }
    }

    func testVolumeWithShiftOptionIsAFineStep() {
        for (key, direction) in volumeKeys {
            XCTAssertEqual(
                route(key, [.shift, .option]),
                .consume(.volumeStep(direction, .fine, invertFeedback: false)))
        }
    }

    func testVolumeWithShiftOnlyInvertsTheFeedbackSound() {
        for (key, direction) in volumeKeys {
            XCTAssertEqual(
                route(key, [.shift]),
                .consume(.volumeStep(direction, .normal, invertFeedback: true)))
        }
    }

    func testVolumeWithOptionOnlyPassesThrough() {
        for (key, _) in volumeKeys {
            XCTAssertEqual(route(key, [.option]), .passThrough)
        }
    }

    // MARK: - Mute

    func testMuteWithoutModifiersOrWithShiftToggles() {
        XCTAssertEqual(route(.mute), .consume(.toggleMute))
        XCTAssertEqual(route(.mute, [.shift]), .consume(.toggleMute))
    }

    func testMuteWithOptionOnlyPassesThrough() {
        XCTAssertEqual(route(.mute, [.option]), .passThrough)
    }

    // MARK: - Brightness

    func testBrightnessWithoutModifiersIsANormalStep() {
        for (key, direction) in brightnessKeys {
            XCTAssertEqual(route(key), .consume(.brightnessStep(direction, .normal)))
        }
    }

    func testBrightnessWithShiftOptionIsAFineStep() {
        for (key, direction) in brightnessKeys {
            XCTAssertEqual(route(key, [.shift, .option]), .consume(.brightnessStep(direction, .fine)))
        }
    }

    func testBrightnessWithOptionOnlyPassesThrough() {
        for (key, _) in brightnessKeys {
            XCTAssertEqual(route(key, [.option]), .passThrough)
        }
    }

    func testBrightnessWithAnyControlPassesThrough() {
        let combinations: [KeyModifiers] = [
            [.control], [.control, .shift], [.control, .option], [.control, .shift, .option],
            [.control, .command], [.control, .shift, .option, .command],
        ]
        for (key, _) in brightnessKeys {
            for modifiers in combinations {
                XCTAssertEqual(route(key, modifiers), .passThrough, "\(key) + \(modifiers.rawValue)")
            }
        }
    }

    // MARK: - Everything else

    func testOtherKeysAlwaysPassThrough() {
        let keys: [MediaKey] = [
            .play, .next, .previous, .fast, .rewind,
            .illuminationUp, .illuminationDown, .illuminationToggle,
        ]
        let combinations: [KeyModifiers] = [[], [.shift], [.option], [.shift, .option], [.control], [.command]]
        for key in keys {
            for modifiers in combinations {
                XCTAssertEqual(route(key, modifiers), .passThrough, "\(key) + \(modifiers.rawValue)")
            }
        }
    }

    /// Combinations the table does not list stay with macOS.
    func testUnlistedCombinationsPassThrough() {
        let handled: [MediaKey] = [.soundUp, .soundDown, .mute, .brightnessUp, .brightnessDown]
        let unlisted: [KeyModifiers] = [
            [.control], [.command], [.shift, .command], [.option, .command],
            [.shift, .option, .command], [.shift, .control], [.shift, .option, .control],
        ]
        for key in handled {
            for modifiers in unlisted {
                XCTAssertEqual(route(key, modifiers), .passThrough, "\(key) + \(modifiers.rawValue)")
            }
        }
        XCTAssertEqual(route(.mute, [.shift, .option]), .passThrough)
        XCTAssertEqual(route(.brightnessUp, [.shift]), .passThrough)
        XCTAssertEqual(route(.brightnessDown, [.shift]), .passThrough)
    }

    /// The whole table at once: exactly these combinations are consumed.
    func testExactlyTheListedCombinationsAreConsumed() {
        let allModifiers: [KeyModifiers] = (0..<16).map { KeyModifiers(rawValue: $0) }
        let consumed: [MediaKey: Set<KeyModifiers>] = [
            .soundUp: [[], [.shift], [.shift, .option]],
            .soundDown: [[], [.shift], [.shift, .option]],
            .mute: [[], [.shift]],
            .brightnessUp: [[], [.shift, .option]],
            .brightnessDown: [[], [.shift, .option]],
        ]
        for (key, expected) in consumed {
            for modifiers in allModifiers {
                let isConsumed = route(key, modifiers) != .passThrough
                XCTAssertEqual(isConsumed, expected.contains(modifiers), "\(key) + \(modifiers.rawValue)")
            }
        }
    }

    // MARK: - Feature toggles

    func testDisabledPassesEverythingThrough() {
        let options = RoutingOptions(isEnabled: false)
        for key in [MediaKey.soundUp, .soundDown, .mute, .brightnessUp, .brightnessDown] {
            XCTAssertEqual(route(key, options: options), .passThrough)
        }
    }

    func testVolumeHandlingOffLeavesBrightnessAlone() {
        let options = RoutingOptions(handleVolume: false)
        XCTAssertEqual(route(.soundUp, options: options), .passThrough)
        XCTAssertEqual(route(.soundDown, [.shift], options: options), .passThrough)
        XCTAssertEqual(route(.mute, options: options), .passThrough)
        XCTAssertEqual(route(.brightnessUp, options: options), .consume(.brightnessStep(.up, .normal)))
    }

    func testBrightnessHandlingOffLeavesVolumeAlone() {
        let options = RoutingOptions(handleBrightness: false)
        XCTAssertEqual(route(.brightnessUp, options: options), .passThrough)
        XCTAssertEqual(route(.brightnessDown, [.shift, .option], options: options), .passThrough)
        XCTAssertEqual(
            route(.soundUp, options: options),
            .consume(.volumeStep(.up, .normal, invertFeedback: false)))
        XCTAssertEqual(route(.mute, options: options), .consume(.toggleMute))
    }
}
