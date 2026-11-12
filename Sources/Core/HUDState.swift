import Foundation

enum HUDKind: Equatable, Sendable {
    case volume
    case brightness
}

/// Everything a HUD style needs to draw one frame.
struct HUDState: Equatable, Sendable {
    var kind: HUDKind
    /// 0…1.
    var level: Double
    /// Volume only.
    var isMuted: Bool
    /// Output device or display name.
    var deviceName: String?
    var symbolName: String
    /// SF Symbols `variableValue`.
    var symbolValue: Double
}

extension HUDState {
    static let brightnessSymbol = "sun.max.fill"
    static let mutedSymbol = "speaker.slash.fill"
    static let speakerSymbol = "speaker.wave.3.fill"

    static func volume(_ reading: VolumeReading) -> HUDState {
        HUDState(
            kind: .volume,
            level: reading.level,
            isMuted: reading.isMuted,
            deviceName: reading.deviceName,
            symbolName: volumeSymbol(for: reading),
            symbolValue: reading.isMuted ? 0 : reading.level)
    }

    static func brightness(_ reading: BrightnessReading) -> HUDState {
        HUDState(
            kind: .brightness,
            level: reading.level,
            isMuted: false,
            deviceName: reading.displayName,
            symbolName: brightnessSymbol,
            symbolValue: reading.level)
    }

    /// Icon selection from SPEC §4.3: silence always shows the slashed speaker;
    /// otherwise the device decides.
    static func volumeSymbol(for reading: VolumeReading) -> String {
        if reading.isMuted || reading.level <= 0 { return mutedSymbol }
        let name = reading.deviceName ?? ""
        if name.localizedCaseInsensitiveContains("AirPods Max") { return "airpodsmax" }
        if name.localizedCaseInsensitiveContains("AirPods Pro") { return "airpodspro" }
        if name.localizedCaseInsensitiveContains("AirPods") { return "airpods" }
        switch reading.deviceKind {
        case .bluetooth, .headphones: return "headphones"
        case .speakers, .other: return speakerSymbol
        }
    }
}
