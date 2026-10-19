import XCTest

/// Opens the demo vault's encrypted note, "Exchange 2FA backup codes", whose password is "hello".
final class EncryptedNoteTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_encryptedNote_opensOnlyWithItsPasswordAndLocksAgainWhenClosed() throws {
        let app = XCUIApplication.launchWithDemoVault()
        // The demo vault's only encrypted note. Its recovery phrases and private keys are encrypted items too, so it's
        // told apart from them by its title.
        let note = app.buttons.matching(identifier: AccessibilityIdentifier.Feed.encryptedItem)
            .matching(NSPredicate(format: "label CONTAINS %@", "Exchange 2FA backup codes"))
            .firstMatch
        let password = app.secureTextFields[AccessibilityIdentifier.EncryptedItem.password]
        let decrypt = app.buttons[AccessibilityIdentifier.EncryptedItem.decrypt]
        let error = app.descendants(matching: .any)[AccessibilityIdentifier.EncryptedItem.error]
        let contents = app.descendants(matching: .any)[AccessibilityIdentifier.SecureNote.contents]

        XCTAssertTrue(app.buttons.matching(identifier: AccessibilityIdentifier.Feed.encryptedItem).firstMatch
            .appears(within: 10))
        XCTAssertTrue(app.scrollFeed(toShow: note))
        note.tap()
        XCTAssertTrue(password.appears(within: 5))

        password.tap()
        password.typeText("wrong")
        decrypt.tap()
        // Deriving the key takes a moment, and longer in a debug build on a busy Mac.
        XCTAssertTrue(error.appears(within: 20))
        XCTAssertFalse(contents.exists)

        password.tap()
        password.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "wrong".count) + "hello")
        decrypt.tap()
        XCTAssertTrue(contents.appears(within: 20))

        // Closing the note locks it again.
        app.buttons[AccessibilityIdentifier.Detail.done].tap()
        XCTAssertTrue(contents.disappears(within: 5))
        note.tap()
        XCTAssertTrue(password.appears(within: 5))
        XCTAssertFalse(contents.exists)
    }
}
