import XCTest
@testable import ModernMac

final class HUDStateTests: XCTestCase {
    private func symbol(
        level: Double = 0.5, muted: Bool = false, name: String? = "MacBook Air Speakers",
        kind: OutputDeviceKind = .speakers
    ) -> String {
        HUDState.volumeSymbol(
            for: VolumeReading(level: level, isMuted: muted, deviceName: name, deviceKind: kind))
    }

    func testSpeakersUseTheSpeakerSymbol() {
        XCTAssertEqual(symbol(), "speaker.wave.3.fill")
        XCTAssertEqual(symbol(name: nil, kind: .other), "speaker.wave.3.fill")
    }

    func testMutedOrZeroShowsTheSlashedSpeakerWhateverTheDevice() {
        XCTAssertEqual(symbol(muted: true), "speaker.slash.fill")
        XCTAssertEqual(symbol(level: 0), "speaker.slash.fill")
        XCTAssertEqual(symbol(muted: true, name: "Ando's AirPods Pro", kind: .bluetooth), "speaker.slash.fill")
        XCTAssertEqual(symbol(level: 0, name: "External Headphones", kind: .headphones), "speaker.slash.fill")
    }

    func testAirPodsModelsAreToldApart() {
        XCTAssertEqual(symbol(name: "Ando's AirPods Max", kind: .bluetooth), "airpodsmax")
        XCTAssertEqual(symbol(name: "Ando's AirPods Pro", kind: .bluetooth), "airpodspro")
        XCTAssertEqual(symbol(name: "Ando's AirPods", kind: .bluetooth), "airpods")
        XCTAssertEqual(symbol(name: "airpods pro de Ando", kind: .bluetooth), "airpodspro")
    }

    func testOtherBluetoothAndHeadphonePortUseHeadphones() {
        XCTAssertEqual(symbol(name: "WH-1000XM5", kind: .bluetooth), "headphones")
        XCTAssertEqual(symbol(name: "External Headphones", kind: .headphones), "headphones")
    }

    func testVolumeStateCarriesLevelAndVariableValue() {
        let state = HUDState.volume(
            VolumeReading(level: 0.25, isMuted: false, deviceName: "Speakers"))
        XCTAssertEqual(state.kind, .volume)
        XCTAssertEqual(state.level, 0.25)
        XCTAssertEqual(state.symbolValue, 0.25)
        XCTAssertEqual(state.deviceName, "Speakers")
    }

    func testMutedVolumeKeepsItsLevelButDrawsAnEmptySymbol() {
        let state = HUDState.volume(VolumeReading(level: 0.75, isMuted: true, deviceName: nil))
        XCTAssertEqual(state.level, 0.75)
        XCTAssertTrue(state.isMuted)
        XCTAssertEqual(state.symbolValue, 0)
    }

    func testBrightnessState() {
        let state = HUDState.brightness(
            BrightnessReading(level: 0.6, displayID: 1, displayName: "Built-in Retina Display"))
        XCTAssertEqual(state.kind, .brightness)
        XCTAssertEqual(state.level, 0.6)
        XCTAssertFalse(state.isMuted)
        XCTAssertEqual(state.symbolName, "sun.max.fill")
        XCTAssertEqual(state.symbolValue, 0.6)
        XCTAssertEqual(state.deviceName, "Built-in Retina Display")
    }
}
