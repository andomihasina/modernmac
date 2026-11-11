import XCTest

/// Placeholder so `make test` exercises the hosted test setup from day one.
/// Real suites arrive with the engine in Phase 1.
final class SmokeTests: XCTestCase {
    func testRunsInsideTheApp() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.ando.ModernMac")
    }
}
