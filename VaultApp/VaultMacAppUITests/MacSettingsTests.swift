import XCTest

/// The Settings window, on a vault of the tests' own.
final class MacSettingsTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The tabs are in the window's toolbar, every row starts below it, and the Security tab's last row can be reached.
    @MainActor
    func test_settings_showsEveryRowBelowItsTabs() throws {
        let app = XCUIApplication.launchedOnAFreshVault()
        app.setAppLockPassword()

        app.typeKey(",", modifierFlags: .command)
        let codeTapAction = app.popUpButtons["settings.code-tap-action"]
        XCTAssertTrue(codeTapAction.waitForExistence(timeout: 5))
        let tabs = app.toolbars.firstMatch
        XCTAssertTrue(tabs.exists)
        XCTAssertGreaterThanOrEqual(codeTapAction.frame.minY, tabs.frame.maxY)
        XCTAssertTrue(codeTapAction.isHittable)

        tabs.descendants(matching: .any)["Security"].firstMatch.click()
        let requireUnlock = app.popUpButtons["settings.require-unlock"]
        XCTAssertTrue(requireUnlock.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(requireUnlock.frame.minY, tabs.frame.maxY)
        let deleteAllData = app.buttons["settings.delete-all-data"]
        XCTAssertTrue(deleteAllData.exists)
        XCTAssertTrue(deleteAllData.isHittable)
    }
}
