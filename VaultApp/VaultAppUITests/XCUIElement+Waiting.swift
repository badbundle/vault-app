import XCTest

extension XCUIElement {
    /// Whether the element is there, or appears within `timeout`.
    ///
    /// `waitForExistence(timeout:)` first checks after a second, even for an element that's already there, and most
    /// are: XCUITest waits for the app to settle after every action.
    func appears(within timeout: TimeInterval) -> Bool {
        exists || waitForExistence(timeout: timeout)
    }

    /// Whether the element has gone, or goes within `timeout`.
    func disappears(within timeout: TimeInterval) -> Bool {
        !exists || waitForNonExistence(timeout: timeout)
    }
}
