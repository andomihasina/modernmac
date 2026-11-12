import Foundation

/// Why a hardware call could not be carried out. Any of these makes the key
/// pass through to macOS (fail open).
enum HardwareError: Error, Equatable {
    /// No output device, or no display that can be adjusted.
    case noDevice
    /// The device exists but its level cannot be set (HDMI, some USB DACs).
    case notSettable
    /// The API needed is missing on this system.
    case unavailable
    /// The system call returned an error status.
    case failed(status: Int32)
}

enum OutputDeviceKind: Equatable, Sendable {
    case speakers
    case headphones
    case bluetooth
    case other
}

struct VolumeReading: Equatable, Sendable {
    /// 0…1, the same scale as the system slider.
    var level: Double
    var isMuted: Bool
    var deviceName: String?
    var deviceKind: OutputDeviceKind = .speakers
}

struct BrightnessReading: Equatable, Sendable {
    /// 0…1.
    var level: Double
    /// The `CGDirectDisplayID` that was read; pass it back to `setLevel`.
    var displayID: UInt32
    var displayName: String?
}

/// The default output device's volume.
@MainActor
protocol VolumeControlling: AnyObject {
    /// Throws when there is no output device or its volume cannot be set.
    func read() throws -> VolumeReading
    func setLevel(_ level: Double) throws
    func setMuted(_ isMuted: Bool) throws
}

/// The brightness of the display the keys should act on.
@MainActor
protocol BrightnessControlling: AnyObject {
    /// False when the private API is missing; brightness keys then pass through.
    var isAvailable: Bool { get }
    /// Reads the target display. Throws when no display can be adjusted.
    func read() throws -> BrightnessReading
    func setLevel(_ level: Double, displayID: UInt32) throws
}

@MainActor
protocol FeedbackSoundPlaying: AnyObject {
    func play()
}
