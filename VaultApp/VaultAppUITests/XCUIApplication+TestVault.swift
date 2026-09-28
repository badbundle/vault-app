import XCTest

/// A vault with the lock on, which the app prepares for a test (see `UITestVault`) in storage of its own, so the
/// simulator's own vault is never read or written.
enum TestVault: String {
    /// App Lock on, asking for device authentication only, over the demo vault.
    case appLock = "app-lock"
    /// The App Lock Password set over the demo vault, and a duress password, which opens a vault with a code and a note
    /// of its own.
    case appLockPassword = "app-lock-password"

    static let password = "correct horse battery"
    static let duressPassword = "plausible decoy"
}

/// How device authentication answers a prompt in the app.
enum Authentication: String {
    /// The user passes, as with a face that's recognised.
    case allow
    /// The user doesn't pass, as with a face that isn't.
    case deny
    /// The user dismisses the prompt.
    case cancel
    /// The device has no passcode, so it can't ask. Only on its own.
    case unavailable
}

extension XCUIApplication {
    /// Has the app prepare `vault` in a launch of its own, then launches it on that vault, as it starts on a device.
    ///
    /// - Parameters:
    ///   - authentication: How device authentication answers each prompt in turn. The last answers every prompt after
    ///     it.
    ///   - appLockDelay: Require Unlock, in seconds, if not the default, which is immediately.
    static func launch(
        preparing vault: TestVault,
        authentication: [Authentication],
        appLockDelay: Int? = nil,
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-test-vault", vault.rawValue]
        app.launch()
        XCTAssertTrue(app.staticTexts[AccessibilityIdentifier.testVaultPrepared].appears(within: 30))
        app.relaunch(authentication: authentication, appLockDelay: appLockDelay)
        return app
    }

    /// Launches the app again on the vault it prepared last.
    func relaunch(authentication: [Authentication], appLockDelay: Int? = nil) {
        launchArguments = [
            "-ui-test-vault", "open",
            "-ui-test-authentication", authentication.map(\.rawValue).joined(separator: ","),
        ]
        if let appLockDelay {
            launchArguments += ["-ui-test-app-lock-delay", "\(appLockDelay)"]
        }
        launch()
    }

    /// Whether anything of a vault is in the accessibility tree: the feed, the sidebar, or the name of an item.
    var showsAnythingOfTheVault: Bool {
        let vault = NSPredicate(
            format: "identifier BEGINSWITH 'feed.' OR identifier BEGINSWITH 'sidebar.'"
                + " OR label CONTAINS 'GitHub' OR label CONTAINS 'Recovery codes' OR label CONTAINS 'mcky.dev'",
        )
        return descendants(matching: .any).matching(vault).firstMatch.exists
    }
}
