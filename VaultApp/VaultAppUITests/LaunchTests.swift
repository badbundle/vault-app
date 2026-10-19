import XCTest

/// Launches the app and goes to its main screens and back, to check it starts and gets around.
final class LaunchTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func test_launch_opensOnTheFeed() throws {
        let app = XCUIApplication.launchWithDemoVault()
        let codes = app.buttons.matching(identifier: AccessibilityIdentifier.Feed.otpCode)
        let code = codes.firstMatch
        let back = app.navigationBars.buttons["BackButton"]

        // The demo vault starts with its recovery phrases and private keys, and its codes are further down.
        XCTAssertTrue(app.buttons.matching(identifier: AccessibilityIdentifier.Feed.encryptedItem).firstMatch
            .appears(within: 10))
        XCTAssertTrue(app.scrollFeed(toShow: code))
        XCTAssertGreaterThan(codes.count, 1)

        // The feed is on top of the sidebar, which has Settings. Tapping a code copies it unless Settings says to
        // show its details instead. Its touch and hold menu has them too, but once that menu is open XCUITest waits
        // for the app to go idle until the test times out.
        back.tap()
        app.buttons[AccessibilityIdentifier.Sidebar.settings].tap()
        XCTAssertTrue(app.collectionViews[AccessibilityIdentifier.Settings.list].appears(within: 5))
        app.buttons[AccessibilityIdentifier.Settings.codeTapAction].tap()
        app.buttons[AccessibilityIdentifier.Settings.codeTapActionShowDetails].tap()
        back.tap()
        app.buttons[AccessibilityIdentifier.Sidebar.items].tap()

        XCTAssertTrue(app.scrollFeed(toShow: code))
        code.tap()
        let done = app.buttons[AccessibilityIdentifier.Detail.done]
        XCTAssertTrue(done.appears(within: 5))
        done.tap()
        XCTAssertTrue(done.disappears(within: 5))

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(code.wait(for: \.isHittable, toEqual: true, timeout: 5))
    }
}
