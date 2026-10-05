import XCTest

/// What the Mac app's windows show once it's locked, on a vault of the tests' own.
final class MacWindowPrivacyTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_locking_leavesNoWindowShowingAnythingFromTheVault() throws {
        let app = XCUIApplication.launchedOnAFreshVault()
        app.setAppLockPassword()

        // A note, open on its page.
        app.typeKey("n", modifierFlags: [.shift, .command])
        let contents = app.textViews["editor.contents"]
        XCTAssertTrue(contents.waitForExistence(timeout: 5))
        contents.click()
        app.typeText("Private plans\nNothing to see")
        app.buttons["editor.save"].click()
        let row = app.descendants(matching: .any).matching(identifier: "feed.item").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()
        XCTAssertTrue(app.staticTexts["detail.title"].waitForExistence(timeout: 5))
        // And Settings.
        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.windows.count >= 2)

        // Lock Vault, in the Vault menu.
        app.typeKey("l", modifierFlags: [.control, .command])

        XCTAssertTrue(app.buttons["app-lock.unlock"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["locked-window"].exists)
        XCTAssertFalse(app.staticTexts["detail.title"].exists)
        XCTAssertFalse(row.exists)
        XCTAssertFalse(app.descendants(matching: .any)["sidebar.items"].exists)
        for window in app.windows.allElementsBoundByIndex {
            XCTAssertFalse(window.title.contains("Private"), window.title)
        }
    }

    /// The title is only ever "Vault", whatever's open.
    @MainActor
    func test_openItem_isNeverInTheWindowsTitle() throws {
        let app = XCUIApplication.launchedOnAFreshVault()
        app.setAppLockPassword()
        app.typeKey("n", modifierFlags: [.shift, .command])
        let contents = app.textViews["editor.contents"]
        XCTAssertTrue(contents.waitForExistence(timeout: 5))
        contents.click()
        app.typeText("Private plans")
        app.buttons["editor.save"].click()
        let row = app.descendants(matching: .any).matching(identifier: "feed.item").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()
        XCTAssertTrue(app.staticTexts["detail.title"].waitForExistence(timeout: 5))

        XCTAssertEqual(app.windows.allElementsBoundByIndex.map(\.title), ["Vault"])
    }
}
