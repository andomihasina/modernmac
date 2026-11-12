import AppKit
import CoreGraphics

/// Brightness of the display the keys should act on, through `DisplayServicesBridge`.
@MainActor
final class BrightnessController: BrightnessControlling {
    var isAvailable: Bool { DisplayServicesBridge.isUsable }

    func read() throws -> BrightnessReading {
        guard isAvailable else { throw HardwareError.unavailable }
        guard let display = targetDisplay() else { throw HardwareError.noDevice }
        var level: Float = 0
        guard let status = DisplayServicesBridge.getBrightness(display, into: &level) else {
            throw HardwareError.unavailable
        }
        guard status == 0 else { throw HardwareError.failed(status: status) }
        return BrightnessReading(
            level: Double(level), displayID: display, displayName: Self.name(of: display))
    }

    func setLevel(_ level: Double, displayID: UInt32) throws {
        let value = Float(min(max(level, 0), 1))
        guard let status = DisplayServicesBridge.setBrightness(displayID, to: value) else {
            throw HardwareError.unavailable
        }
        guard status == 0 else { throw HardwareError.failed(status: status) }
        // Absent on macOS 15.7.8, where System Settings follows without it (FINDINGS V3).
        DisplayServicesBridge.notifyBrightnessChanged(displayID, to: value)
    }

    /// The display under the pointer if it can be adjusted, otherwise the
    /// built-in display, otherwise none.
    private func targetDisplay() -> CGDirectDisplayID? {
        if let pointer = CGEvent(source: nil)?.location {
            var display: CGDirectDisplayID = 0
            var count: UInt32 = 0
            if CGGetDisplaysWithPoint(pointer, 1, &display, &count) == .success, count > 0,
               DisplayServicesBridge.canChangeBrightness(display) == true {
                return display
            }
        }

        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return nil }
        return displays.prefix(Int(count)).first {
            CGDisplayIsBuiltin($0) != 0 && DisplayServicesBridge.canChangeBrightness($0) == true
        }
    }

    private static func name(of display: CGDirectDisplayID) -> String? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return NSScreen.screens.first {
            ($0.deviceDescription[key] as? NSNumber)?.uint32Value == display
        }?.localizedName
    }
}
