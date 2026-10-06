import XCTest

/// The Mac app's first launch, which sets the App Lock Password, and its lock screen, on a vault of the tests' own.
final class MacAppLockTests: XCTestCase {
    private let password = "correct horse battery"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_firstLaunch_setsThePasswordThenLocksAndUnlocksWithIt() throws {
        let app = XCUIApplication.launchedOnAFreshVault()

        let setPassword = app.buttons["first-launch.set-password"]
        XCTAssertTrue(setPassword.waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["sidebar.items"].exists)
        XCTAssertFalse(setPassword.isEnabled)
        app.secureTextFields["first-launch.password"].click()
        app.typeText(password)
        app.secureTextFields["first-launch.confirmation"].click()
        app.typeText(password)
        setPassword.click()
        XCTAssertTrue(app.descendants(matching: .any)["sidebar.items"].waitForExistence(timeout: 10))

        // Lock Vault, in the Vault menu.
        app.typeKey("l", modifierFlags: [.control, .command])
        let unlock = app.buttons["app-lock.unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["sidebar.items"].exists)

        // Touch ID or the Mac's password, then the App Lock Password.
        unlock.click()
        let field = app.secureTextFields["app-lock.password"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        app.typeText("not the password")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.staticTexts["app-lock.message.wrong-password"].waitForExistence(timeout: 5))
        field.click()
        app.typeText(password)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.descendants(matching: .any)["sidebar.items"].waitForExistence(timeout: 10))
    }

    @MainActor
    func test_firstLaunch_withAShortPassword_cantBeSet() throws {
        let app = XCUIApplication.launchedOnAFreshVault()

        let setPassword = app.buttons["first-launch.set-password"]
        XCTAssertTrue(setPassword.waitForExistence(timeout: 10))
        app.secureTextFields["first-launch.password"].click()
        app.typeText("short")
        app.secureTextFields["first-launch.confirmation"].click()
        app.typeText("short")

        XCTAssertFalse(setPassword.isEnabled)
    }
}

extension XCUIApplication {
    /// The Mac app, launched on an empty vault of the tests' own, as on its first launch, with Touch ID or the Mac's
    /// password answering `authentication` (see `VaultMacUITestVault`).
    ///
    /// It ignores any state macOS saved for the app when it last ran, as Xcode's "Launch application without state
    /// restoration" does. Launched by the tests rather than from the Finder or the Dock, the app opens no window at
    /// all if macOS has saved state for it, as it can once the app has been stopped by a test.
    @MainActor
    static func launchedOnAFreshVault(authentication: String = "allow") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-test-vault", "fresh",
            "-ui-test-authentication", authentication,
            "-ApplePersistenceIgnoreState", "YES",
        ]
        app.launch()
        return app
    }
}
