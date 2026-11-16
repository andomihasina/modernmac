#if DEBUG
import XCTest
@testable import ModernMac

final class SimulateRequestTests: XCTestCase {
    private func request(_ query: String) -> SimulateRequest? {
        URL(string: "modernmac://simulate?\(query)").flatMap(SimulateRequest.init(url:))
    }

    func testVolumeRequest() {
        let parsed = request("kind=volume&level=0.6&style=tahoe")
        XCTAssertEqual(parsed?.kind, .volume)
        XCTAssertEqual(parsed?.level, 0.6)
        XCTAssertEqual(parsed?.isMuted, false)
        XCTAssertEqual(parsed?.style, .tahoe)
        XCTAssertNil(parsed?.hold)
    }

    func testBrightnessMutedAndHold() {
        let parsed = request("kind=brightness&level=1&muted=1&hold=5")
        XCTAssertEqual(parsed?.kind, .brightness)
        XCTAssertEqual(parsed?.level, 1)
        XCTAssertEqual(parsed?.isMuted, true)
        XCTAssertEqual(parsed?.hold, 5)
    }

    func testDefaultsWithoutAQuery() {
        let parsed = URL(string: "modernmac://simulate").flatMap(SimulateRequest.init(url:))
        XCTAssertEqual(parsed?.kind, .volume)
        XCTAssertEqual(parsed?.level, 0.5)
    }

    func testLevelIsClamped() {
        XCTAssertEqual(request("level=7")?.level, 1)
        XCTAssertEqual(request("level=-1")?.level, 0)
    }

    func testOptionOverrides() {
        let parsed = request("position=bottomCenter&percent=1&name=1&interactive=0")
        var base = HUDOptions()
        base.style = .tahoe
        let options = parsed?.options(over: base)
        XCTAssertEqual(options?.position, .bottomCenter)
        XCTAssertEqual(options?.showsPercentage, true)
        XCTAssertEqual(options?.showsDeviceName, true)
        XCTAssertEqual(options?.isInteractive, false)
        XCTAssertEqual(options?.style, .tahoe)
    }

    func testPillFlag() {
        XCTAssertEqual(request("style=notch&pill=1")?.forcesPill, true)
        XCTAssertEqual(request("style=notch")?.forcesPill, false)
        XCTAssertNil(request("pill=yes"))
    }

    func testOptionsStayAsTheyAreWithoutOverrides() {
        var base = HUDOptions()
        base.position = .topLeft
        base.showsPercentage = true
        XCTAssertEqual(request("level=0.2")?.options(over: base), base)
    }

    func testStateMatchesWhatAKeyPressProduces() {
        let muted = request("kind=volume&level=0.4&muted=1")?.state
        XCTAssertEqual(muted?.kind, .volume)
        XCTAssertEqual(muted?.isMuted, true)
        XCTAssertEqual(muted?.symbolName, HUDState.mutedSymbol)

        let brightness = request("kind=brightness&level=0.4")?.state
        XCTAssertEqual(brightness?.kind, .brightness)
        XCTAssertEqual(brightness?.symbolName, HUDState.brightnessSymbol)
    }

    func testUnreadableRequestsAreRejected() {
        XCTAssertNil(request("kind=contrast"))
        XCTAssertNil(request("level=loud"))
        XCTAssertNil(request("muted=maybe"))
        XCTAssertNil(request("style=glass"))
        XCTAssertNil(request("hold=0"))
        XCTAssertNil(request("unknown=1"))
        XCTAssertNil(URL(string: "modernmac://other?level=1").flatMap(SimulateRequest.init(url:)))
        XCTAssertNil(URL(string: "https://simulate?level=1").flatMap(SimulateRequest.init(url:)))
    }

    // MARK: - Other debug URLs

    private func command(_ text: String) -> DebugCommand? {
        URL(string: text).flatMap(DebugCommand.init(url:))
    }

    func testShowWindowCommands() {
        XCTAssertEqual(command("modernmac://show?window=settings"), .show(.settings))
        XCTAssertEqual(command("modernmac://show?window=onboarding"), .show(.onboarding))
        XCTAssertNil(command("modernmac://show?window=about"))
        XCTAssertNil(command("modernmac://show"))
    }

    func testMenuBarIconCommand() {
        XCTAssertEqual(command("modernmac://set?showMenuBarIcon=0"), .setMenuBarIcon(false))
        XCTAssertEqual(command("modernmac://set?showMenuBarIcon=1"), .setMenuBarIcon(true))
        XCTAssertNil(command("modernmac://set?showMenuBarIcon=maybe"))
        XCTAssertNil(command("modernmac://set?style=notch"))
    }

    func testCommandsAndSimulateRequestsDoNotOverlap() {
        XCTAssertNil(command("modernmac://simulate?kind=volume"))
        XCTAssertNil(request("window=settings"))
        XCTAssertNil(URL(string: "modernmac://show?window=settings").flatMap(SimulateRequest.init(url:)))
        XCTAssertNil(command("other://show?window=settings"))
    }
}
#endif
