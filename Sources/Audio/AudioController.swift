import AudioToolbox
import CoreAudio
import Foundation

/// Volume and mute of the default output device, through public CoreAudio API.
///
/// What a device can do (settable volume, mute), its name and its kind are
/// read once when it becomes the default and cached, so a key press costs one
/// read and one write. Property listeners keep the cache right and report
/// changes made elsewhere (Control Center, another app, the device itself).
@MainActor
final class AudioController: VolumeControlling {
    /// The level, mute state or default device changed. Also fires for our own writes.
    var onChange: ((VolumeReading) -> Void)?

    private static let systemObject = AudioObjectID(kAudioObjectSystemObject)
    private static let unknownDevice = AudioDeviceID(kAudioObjectUnknown)
    /// 'hdpn': the built-in output is routed to the headphone port.
    private static let headphonesDataSource: UInt32 = 0x6864_706E

    private static let defaultDeviceAddress = address(
        kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
    private static let volumeAddress = address(
        kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
    private static let muteAddress = address(
        kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
    private static let dataSourceAddress = address(
        kAudioDevicePropertyDataSource, scope: kAudioDevicePropertyScopeOutput)
    private static let transportAddress = address(
        kAudioDevicePropertyTransportType, scope: kAudioObjectPropertyScopeGlobal)
    private static let nameAddress = address(
        kAudioObjectPropertyName, scope: kAudioObjectPropertyScopeGlobal)

    private var device = AudioController.unknownDevice
    private var deviceName: String?
    private var deviceKind = OutputDeviceKind.other
    private var isVolumeSettable = false
    private var hasMute = false
    private var isMuteSettable = false

    private var defaultDeviceListener: AudioObjectPropertyListenerBlock?
    private var deviceListeners: [(address: AudioObjectPropertyAddress, block: AudioObjectPropertyListenerBlock)] = []

    /// Resolves the default device and starts listening. Doing this at launch
    /// also opens the connection to the audio server, which otherwise makes
    /// the first key press slow (about 150 ms in the Phase 0 spike).
    init() {
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.defaultDeviceDidChange() }
        }
        var address = Self.defaultDeviceAddress
        let status = AudioObjectAddPropertyListenerBlock(
            Self.systemObject, &address, DispatchQueue.main, listener)
        if status == noErr {
            defaultDeviceListener = listener
        } else {
            Log.audio.error("Could not listen for default device changes: \(status)")
        }
        attach(to: Self.currentDefaultDevice())
    }

    // MARK: - VolumeControlling

    func read() throws -> VolumeReading {
        guard device != Self.unknownDevice else { throw HardwareError.noDevice }
        guard isVolumeSettable else { throw HardwareError.notSettable }
        var level: Float32 = 0
        let status = Self.get(Self.volumeAddress, from: device, into: &level)
        guard status == noErr else { throw HardwareError.failed(status: status) }
        return VolumeReading(
            level: Double(level), isMuted: readMuted(),
            deviceName: deviceName, deviceKind: deviceKind)
    }

    func setLevel(_ level: Double) throws {
        guard device != Self.unknownDevice else { throw HardwareError.noDevice }
        guard isVolumeSettable else { throw HardwareError.notSettable }
        let status = Self.set(Self.volumeAddress, on: device, to: Float32(min(max(level, 0), 1)))
        guard status == noErr else { throw HardwareError.failed(status: status) }
    }

    func setMuted(_ isMuted: Bool) throws {
        guard device != Self.unknownDevice else { throw HardwareError.noDevice }
        guard hasMute, isMuteSettable else { throw HardwareError.notSettable }
        let status = Self.set(Self.muteAddress, on: device, to: UInt32(isMuted ? 1 : 0))
        guard status == noErr else { throw HardwareError.failed(status: status) }
    }

    // MARK: - Device tracking

    private func defaultDeviceDidChange() {
        let newDevice = Self.currentDefaultDevice()
        guard newDevice != device else { return }
        attach(to: newDevice)
        notifyChange()
    }

    private func attach(to newDevice: AudioDeviceID) {
        for listener in deviceListeners {
            var address = listener.address
            AudioObjectRemovePropertyListenerBlock(device, &address, DispatchQueue.main, listener.block)
        }
        deviceListeners.removeAll()

        device = newDevice
        guard newDevice != Self.unknownDevice else {
            deviceName = nil
            deviceKind = .other
            isVolumeSettable = false
            hasMute = false
            isMuteSettable = false
            Log.audio.notice("No default output device")
            return
        }

        refreshDescription()
        isVolumeSettable = Self.isSettable(Self.volumeAddress, on: newDevice)
        hasMute = Self.has(Self.muteAddress, on: newDevice)
        isMuteSettable = hasMute && Self.isSettable(Self.muteAddress, on: newDevice)

        listen(to: Self.volumeAddress) { $0.notifyChange() }
        listen(to: Self.muteAddress) { $0.notifyChange() }
        // Plugging headphones into the built-in port changes the icon, not the device.
        listen(to: Self.dataSourceAddress) {
            $0.refreshDescription()
            $0.notifyChange()
        }

        let name = deviceName ?? "?"
        Log.audio.notice(
            "Output device \(newDevice): \(name, privacy: .public), volume settable=\(self.isVolumeSettable), mute settable=\(self.isMuteSettable)")
    }

    private func listen(
        to address: AudioObjectPropertyAddress, _ action: @escaping @MainActor (AudioController) -> Void
    ) {
        guard Self.has(address, on: device) else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                if let self { action(self) }
            }
        }
        var address = address
        if AudioObjectAddPropertyListenerBlock(device, &address, DispatchQueue.main, block) == noErr {
            deviceListeners.append((address, block))
        }
    }

    private func refreshDescription() {
        deviceName = Self.name(of: device)
        deviceKind = Self.kind(of: device, name: deviceName)
    }

    private func notifyChange() {
        guard let onChange, let reading = try? read() else { return }
        onChange(reading)
    }

    private func readMuted() -> Bool {
        guard hasMute else { return false }
        var muted: UInt32 = 0
        return Self.get(Self.muteAddress, from: device, into: &muted) == noErr && muted != 0
    }

    // MARK: - CoreAudio plumbing

    private static func address(
        _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func currentDefaultDevice() -> AudioDeviceID {
        var device = unknownDevice
        let status = get(defaultDeviceAddress, from: systemObject, into: &device)
        return status == noErr ? device : unknownDevice
    }

    private static func has(_ address: AudioObjectPropertyAddress, on object: AudioObjectID) -> Bool {
        var address = address
        return AudioObjectHasProperty(object, &address)
    }

    private static func isSettable(
        _ address: AudioObjectPropertyAddress, on object: AudioObjectID
    ) -> Bool {
        var address = address
        var settable: DarwinBoolean = false
        return AudioObjectHasProperty(object, &address)
            && AudioObjectIsPropertySettable(object, &address, &settable) == noErr
            && settable.boolValue
    }

    private static func get<T>(
        _ address: AudioObjectPropertyAddress, from object: AudioObjectID, into value: inout T
    ) -> OSStatus {
        var address = address
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
        }
    }

    private static func set<T>(
        _ address: AudioObjectPropertyAddress, on object: AudioObjectID, to value: T
    ) -> OSStatus {
        var address = address
        var value = value
        let size = UInt32(MemoryLayout<T>.size)
        return withUnsafePointer(to: &value) {
            AudioObjectSetPropertyData(object, &address, 0, nil, size, $0)
        }
    }

    private static func name(of device: AudioDeviceID) -> String? {
        var name: Unmanaged<CFString>?
        guard get(nameAddress, from: device, into: &name) == noErr else { return nil }
        return name?.takeRetainedValue() as String?
    }

    private static func kind(of device: AudioDeviceID, name: String?) -> OutputDeviceKind {
        var transport: UInt32 = 0
        _ = get(transportAddress, from: device, into: &transport)
        if transport == kAudioDeviceTransportTypeBluetooth
            || transport == kAudioDeviceTransportTypeBluetoothLE {
            return .bluetooth
        }

        var dataSource: UInt32 = 0
        if has(dataSourceAddress, on: device),
           get(dataSourceAddress, from: device, into: &dataSource) == noErr,
           dataSource == headphonesDataSource {
            return .headphones
        }
        // Apple silicon Macs expose the headphone port as its own device.
        if name?.localizedCaseInsensitiveContains("headphone") == true { return .headphones }
        return transport == kAudioDeviceTransportTypeBuiltIn ? .speakers : .other
    }
}
