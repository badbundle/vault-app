import XCTest

/// Launches the Mac app and checks its main window opens.
final class MacLaunchTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_launch_opensTheMainWindow() throws {
        let app = XCUIApplication.launchedOnAFreshVault()

        // The first launch sets the App Lock Password before anything else.
        let window = app.windows["Vault"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        XCTAssertTrue(window.buttons["first-launch.set-password"].exists)
    }
}
