import XCTest

/// Adding items in the Mac app, on a vault of the tests' own.
final class MacItemEditingTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_newCode_typedIn_isListedWithItsCode() throws {
        let app = XCUIApplication.launchedOnAFreshVault()
        app.setAppLockPassword()

        // New Code, in the File menu.
        app.typeKey("n", modifierFlags: .command)
        let secret = app.textFields["editor.secret"]
        XCTAssertTrue(secret.waitForExistence(timeout: 5))
        let save = app.buttons["editor.save"]
        XCTAssertFalse(save.isEnabled)
        secret.click()
        app.typeText("JBSWY3DPEHPK3PXP")
        app.textFields["editor.issuer"].click()
        app.typeText("Example")
        XCTAssertTrue(save.isEnabled)
        save.click()

        XCTAssertTrue(app.descendants(matching: .any)["feed.item.code"].waitForExistence(timeout: 5))
        XCTAssertFalse(secret.exists)
    }

    @MainActor
    func test_newNote_isListedAndOpens() throws {
        let app = XCUIApplication.launchedOnAFreshVault()
        app.setAppLockPassword()

        // New Note, in the File menu.
        app.typeKey("n", modifierFlags: [.shift, .command])
        let contents = app.textViews["editor.contents"]
        XCTAssertTrue(contents.waitForExistence(timeout: 5))
        contents.click()
        app.typeText("Shopping list\nMilk and eggs")
        app.buttons["editor.save"].click()

        let row = app.descendants(matching: .any).matching(identifier: "feed.item").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()
        let title = app.staticTexts["detail.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "Shopping list")
    }
}
