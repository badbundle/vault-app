import XCTest

/// Launches the app with the lock on, as a person finds it: nothing of the vault shows until they've unlocked it.
final class AppLockTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_launch_withAppLockOn_opensOnlyOnceDeviceAuthenticationPasses() throws {
        // The prompt the app asks for as it launches is dismissed, and the next one passes.
        let app = XCUIApplication.launch(preparing: .appLock, authentication: [.cancel, .allow])
        let unlock = app.buttons[AccessibilityIdentifier.AppLock.unlock]

        XCTAssertTrue(unlock.appears(within: 10))
        XCTAssertFalse(app.showsAnythingOfTheVault)

        unlock.tap()
        XCTAssertTrue(app.buttons[AccessibilityIdentifier.Feed.encryptedItem].appears(within: 10))
        XCTAssertTrue(app.showsAnythingOfTheVault)

        // Launched again, device authentication never passes, so it stays locked.
        app.relaunch(authentication: [.deny])
        let failed = app.descendants(matching: .any)[AccessibilityIdentifier.AppLock.failedMessage]
        XCTAssertTrue(failed.appears(within: 10))
        unlock.tap()
        XCTAssertTrue(failed.appears(within: 5))
        XCTAssertFalse(app.showsAnythingOfTheVault)
    }

    @MainActor
    func test_leavingTheApp_withRequireUnlockImmediately_coversTheVaultAndLocksIt() throws {
        // The prompt as the app launches passes, and the one as it comes back is dismissed.
        let app = XCUIApplication.launch(preparing: .appLock, authentication: [.allow, .cancel], appLockDelay: 0)
        let unlock = app.buttons[AccessibilityIdentifier.AppLock.unlock]
        XCTAssertTrue(app.buttons[AccessibilityIdentifier.Feed.encryptedItem].appears(within: 10))

        // In the app switcher, the app's card shows the privacy cover rather than the vault.
        let cover = app.descendants(matching: .any)[AccessibilityIdentifier.AppLock.privacyCover]
        XCTAssertFalse(cover.exists)
        let card = showAppSwitcher()
        XCTAssertTrue(card.appears(within: 5))
        XCTAssertTrue(cover.exists)
        add(XCTAttachment(image: card.screenshot().image))

        // Back from the app switcher, it's still unlocked: it was only inactive.
        card.tap()
        XCTAssertTrue(cover.disappears(within: 5))
        XCTAssertTrue(app.buttons[AccessibilityIdentifier.Feed.encryptedItem].exists)

        // In the background, it locks.
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate()
        XCTAssertTrue(unlock.appears(within: 10))
        XCTAssertFalse(app.showsAnythingOfTheVault)

        // A launch is locked whatever Require Unlock says.
        app.relaunch(authentication: [.cancel], appLockDelay: 15 * 60)
        XCTAssertTrue(unlock.appears(within: 10))
        XCTAssertFalse(app.showsAnythingOfTheVault)
    }

    @MainActor
    func test_appLockPassword_opensOnlyTheVaultItBelongsTo() throws {
        let app = XCUIApplication.launch(preparing: .appLockPassword, authentication: [.allow], appLockDelay: 0)
        let password = app.secureTextFields[AccessibilityIdentifier.AppLock.password]

        // Device authentication passes as the app launches, and the password is next.
        XCTAssertTrue(password.appears(within: 10))
        XCTAssertFalse(app.showsAnythingOfTheVault)

        enter("wrong password", in: app)
        let wrong = app.descendants(matching: .any)[AccessibilityIdentifier.AppLock.wrongPasswordMessage]
        XCTAssertTrue(wrong.appears(within: 10))
        XCTAssertFalse(app.showsAnythingOfTheVault)

        enter(TestVault.password, in: app)
        XCTAssertTrue(app.buttons[AccessibilityIdentifier.Feed.encryptedItem].appears(within: 10))

        // Locked again, the duress password opens the duress vault, with only its own code and note.
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate()
        XCTAssertTrue(password.appears(within: 10))
        enter(TestVault.duressPassword, in: app)
        let notes = app.buttons.matching(identifier: AccessibilityIdentifier.Feed.secureNote)
        XCTAssertTrue(notes.firstMatch.appears(within: 10))
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(app.buttons.matching(identifier: AccessibilityIdentifier.Feed.otpCode).count, 1)
        XCTAssertFalse(app.buttons[AccessibilityIdentifier.Feed.encryptedItem].exists)
    }

    @MainActor
    func test_lockScreen_onADeviceWithoutAPasscode_asksForOneAndNeverForThePassword() throws {
        let app = XCUIApplication.launch(preparing: .appLockPassword, authentication: [.unavailable])
        let unavailable = app.descendants(matching: .any)[AccessibilityIdentifier.AppLock.unavailableMessage]
        let password = app.secureTextFields[AccessibilityIdentifier.AppLock.password]

        XCTAssertTrue(unavailable.appears(within: 10))
        XCTAssertFalse(password.exists)

        app.buttons[AccessibilityIdentifier.AppLock.unlock].tap()
        XCTAssertTrue(unavailable.appears(within: 5))
        XCTAssertFalse(password.exists)
        XCTAssertFalse(app.showsAnythingOfTheVault)
    }

    /// Types into the lock screen's password field, and taps Unlock.
    @MainActor
    private func enter(_ text: String, in app: XCUIApplication) {
        let password = app.secureTextFields[AccessibilityIdentifier.AppLock.password]
        password.tap()
        password.typeText(text)
        app.buttons[AccessibilityIdentifier.AppLock.unlock].tap()
    }

    /// Swipes up from the bottom of the screen and holds, which opens the app switcher.
    ///
    /// - Returns: The app's card in the app switcher.
    @MainActor
    private func showAppSwitcher() -> XCUIElement {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let bottom = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.998))
        let middle = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        bottom.press(forDuration: 0.05, thenDragTo: middle, withVelocity: .slow, thenHoldForDuration: 1)
        return springboard.otherElements
            .matching(NSPredicate(format: "identifier BEGINSWITH 'card:com.badbundle.vault:'"))
            .firstMatch
    }
}
