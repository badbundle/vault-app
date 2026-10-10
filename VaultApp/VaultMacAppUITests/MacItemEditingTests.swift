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

    /// A code added to a list that already has one is listed at its full height, not clipped (VAULT-124).
    @MainActor
    func test_newCode_addedAboveAnother_isListedAtItsFullHeight() throws {
        let app = XCUIApplication.launchedOnAFreshVault()
        app.setAppLockPassword()

        app.addCode(issuer: "First", account: "ada@example.com")
        app.addCode(issuer: "Second", account: "grace@example.com")

        let rows = app.outlines["feed"].outlineRows
        XCTAssertEqual(rows.count, 2)
        for index in 0 ..< rows.count {
            let row = rows.element(boundBy: index)
            let item = row.descendants(matching: .any)["feed.item"]
            XCTAssertTrue(item.exists)
            XCTAssertLessThanOrEqual(row.frame.minY, item.frame.minY, "Row \(index) starts below its content")
            XCTAssertGreaterThanOrEqual(row.frame.maxY, item.frame.maxY, "Row \(index) cuts off its content")
        }
    }
}

extension XCUIApplication {
    /// Adds a code with New Code, and waits for it to be listed.
    @MainActor
    func addCode(issuer: String, account: String) {
        typeKey("n", modifierFlags: .command)
        let secret = textFields["editor.secret"]
        XCTAssertTrue(secret.waitForExistence(timeout: 5))
        secret.click()
        typeText("JBSWY3DPEHPK3PXP")
        textFields["editor.issuer"].click()
        typeText(issuer)
        textFields["editor.account"].click()
        typeText(account)
        buttons["editor.save"].click()
        XCTAssertTrue(staticTexts[issuer].waitForExistence(timeout: 5))
    }
}
