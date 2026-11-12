import Foundation
@testable import ModernMac

@MainActor
final class FakeVolumeController: VolumeControlling {
    var level: Double
    var isMuted: Bool
    var deviceName: String? = "Fake Speakers"
    var deviceKind = OutputDeviceKind.speakers

    /// Set to make the matching call throw.
    var readError: HardwareError?
    var setLevelError: HardwareError?
    var setMutedError: HardwareError?

    private(set) var setLevelCalls: [Double] = []
    private(set) var setMutedCalls: [Bool] = []

    init(level: Double = 0.5, isMuted: Bool = false) {
        self.level = level
        self.isMuted = isMuted
    }

    func read() throws -> VolumeReading {
        if let readError { throw readError }
        return VolumeReading(
            level: level, isMuted: isMuted, deviceName: deviceName, deviceKind: deviceKind)
    }

    func setLevel(_ level: Double) throws {
        if let setLevelError { throw setLevelError }
        setLevelCalls.append(level)
        self.level = level
    }

    func setMuted(_ isMuted: Bool) throws {
        if let setMutedError { throw setMutedError }
        setMutedCalls.append(isMuted)
        self.isMuted = isMuted
    }
}

@MainActor
final class FakeBrightnessController: BrightnessControlling {
    var isAvailable = true
    var level: Double
    var displayID: UInt32 = 7
    var displayName: String? = "Fake Display"

    var readError: HardwareError?
    var setLevelError: HardwareError?

    private(set) var setLevelCalls: [(level: Double, displayID: UInt32)] = []

    init(level: Double = 0.5) {
        self.level = level
    }

    func read() throws -> BrightnessReading {
        if let readError { throw readError }
        return BrightnessReading(level: level, displayID: displayID, displayName: displayName)
    }

    func setLevel(_ level: Double, displayID: UInt32) throws {
        if let setLevelError { throw setLevelError }
        setLevelCalls.append((level, displayID))
        self.level = level
    }
}

@MainActor
final class FakeFeedbackSound: FeedbackSoundPlaying {
    private(set) var playCount = 0

    func play() {
        playCount += 1
    }
}
