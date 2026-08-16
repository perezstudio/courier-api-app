import XCTest

/// Phase 0 smoke test: the app launches and puts up a window.
/// Phase 2 extends this once the real shell exists.
final class CourierUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
    }
}
