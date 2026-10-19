import XCTest

extension XCUIApplication {
    /// Launches the app on the feed of the demo vault that `make screenshots` uses (see `ScreenshotMode`).
    ///
    /// It's an in-memory vault, with App Lock off, so the simulator's own vault is never read or written. Debug builds
    /// only, which is what the tests run. Its recovery phrases and private keys come first, so its notes and codes are
    /// further down the feed (`scrollFeed(toShow:)`).
    static func launchWithDemoVault() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screenshot-scene", "feed"]
        app.launch()
        return app
    }
}
