#if DEBUG
import AudioToolbox
import CoreAudio
import CoreGraphics

/// Throwaway hardware access for the Phase 0 spike. The real controllers
/// (behind protocols, with listeners) arrive in Phase 1.

enum SpikeStep {
    /// One step on the system's grid: clamp((round(current × grid) ± 1) / grid, 0…1).
    static func stepped(_ current: Float, direction: Int, grid: Float = 16) -> Float {
        let next = ((current * grid).rounded() + Float(direction)) / grid
        return min(max(next, 0), 1)
    }
}

enum SpikeAudio {
    static func defaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard status == noErr, device != 0 else { return nil }
        return device
    }

    static func volume(of device: AudioDeviceID) -> Float? {
        get(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, device: device, initial: Float32(0))
    }

    static func setVolume(_ value: Float, on device: AudioDeviceID) -> Bool {
        set(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, device: device, value: Float32(value))
    }

    static func isMuted(_ device: AudioDeviceID) -> Bool? {
        get(kAudioDevicePropertyMute, device: device, initial: UInt32(0)).map { $0 != 0 }
    }

    static func setMuted(_ muted: Bool, on device: AudioDeviceID) -> Bool {
        set(kAudioDevicePropertyMute, device: device, value: UInt32(muted ? 1 : 0))
    }

    private static func outputAddress(
        _ selector: AudioObjectPropertySelector
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
    }

    private static func get<T>(
        _ selector: AudioObjectPropertySelector, device: AudioDeviceID, initial: T
    ) -> T? {
        var address = outputAddress(selector)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0)
        }
        return status == noErr ? value : nil
    }

    private static func set<T>(
        _ selector: AudioObjectPropertySelector, device: AudioDeviceID, value: T
    ) -> Bool {
        var address = outputAddress(selector)
        var isSettable: DarwinBoolean = false
        guard AudioObjectHasProperty(device, &address),
              AudioObjectIsPropertySettable(device, &address, &isSettable) == noErr,
              isSettable.boolValue
        else { return false }
        var value = value
        let size = UInt32(MemoryLayout<T>.size)
        return withUnsafePointer(to: &value) {
            AudioObjectSetPropertyData(device, &address, 0, nil, size, $0)
        } == noErr
    }
}

enum SpikeDisplay {
    /// The built-in display, or the main display when there is none.
    static func targetDisplay() -> CGDirectDisplayID {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &displays, &count)
        return displays.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
    }
}
#endif
