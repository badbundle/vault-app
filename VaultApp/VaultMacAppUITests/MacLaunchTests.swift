import XCTest

/// Launches the Mac app and checks its main window opens, with the sidebar.
final class MacLaunchTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_launch_opensTheMainWindowWithItsSidebar() throws {
        let app = XCUIApplication()
        app.launch()

        let window = app.windows["Vault"]
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        XCTAssertTrue(window.descendants(matching: .any)["sidebar.items"].exists)
        XCTAssertTrue(window.descendants(matching: .any)["sidebar.backups"].exists)
    }
}
