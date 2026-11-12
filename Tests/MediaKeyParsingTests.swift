import XCTest
@testable import ModernMac

final class MediaKeyParsingTests: XCTestCase {
    private func decode(_ data1: Int, subtype: Int = 8, modifiers: KeyModifiers = []) -> MediaKeyEvent? {
        MediaKeyEvent(subtype: subtype, data1: data1, modifiers: modifiers)
    }

    // The data1 values below are the ones logged on Ando's Mac (FINDINGS V1).

    func testKeyDownForEveryHandledKey() {
        let expected: [(data1: Int, key: MediaKey)] = [
            (0x00a00, .soundUp), (0x10a00, .soundDown), (0x20a00, .brightnessUp),
            (0x30a00, .brightnessDown), (0x70a00, .mute),
        ]
        for (data1, key) in expected {
            XCTAssertEqual(
                decode(data1), MediaKeyEvent(key: key, isDown: true, isRepeat: false),
                "data1 0x\(String(data1, radix: 16))")
        }
    }

    func testKeyUpForEveryHandledKey() {
        let expected: [(data1: Int, key: MediaKey)] = [
            (0x00b00, .soundUp), (0x10b00, .soundDown), (0x20b00, .brightnessUp),
            (0x30b00, .brightnessDown), (0x70b00, .mute),
        ]
        for (data1, key) in expected {
            XCTAssertEqual(
                decode(data1), MediaKeyEvent(key: key, isDown: false, isRepeat: false),
                "data1 0x\(String(data1, radix: 16))")
        }
    }

    func testRepeatBit() {
        XCTAssertEqual(decode(0x00a01), MediaKeyEvent(key: .soundUp, isDown: true, isRepeat: true))
        XCTAssertEqual(decode(0x30a01), MediaKeyEvent(key: .brightnessDown, isDown: true, isRepeat: true))
        XCTAssertEqual(decode(0x00a00)?.isRepeat, false)
    }

    func testOtherKnownKeysDecode() {
        XCTAssertEqual(decode(0x100a00)?.key, .play)
        XCTAssertEqual(decode(0x110a00)?.key, .next)
        XCTAssertEqual(decode(0x120a00)?.key, .previous)
        XCTAssertEqual(decode(0x150a00)?.key, .illuminationUp)
        XCTAssertEqual(decode(0x160a00)?.key, .illuminationDown)
        XCTAssertEqual(decode(0x170a00)?.key, .illuminationToggle)
    }

    func testModifiersAreCarried() {
        XCTAssertEqual(decode(0x00a00, modifiers: [.shift, .option])?.modifiers, [.shift, .option])
    }

    func testOtherSubtypesAreNotMediaKeys() {
        // Subtypes 7, 18 and 19 arrive through the same event mask (FINDINGS V1).
        XCTAssertNil(decode(0x1, subtype: 7))
        XCTAssertNil(decode(0x0, subtype: 18))
        XCTAssertNil(decode(0x00a00, subtype: 19))
    }

    func testUnknownKeyCodeIsRejected() {
        XCTAssertNil(decode(0x40a00))   // key code 4
        XCTAssertNil(decode(0x630a00))  // key code 99
    }

    func testUnknownKeyStateIsRejected() {
        XCTAssertNil(decode(0x00000))
        XCTAssertNil(decode(0x00c00))
    }

    func testHighBitsAboveTheKeyCodeAreRejected() {
        // Bits above the 16-bit key code field make a different, unknown code.
        XCTAssertNil(decode(-1))
    }
}
