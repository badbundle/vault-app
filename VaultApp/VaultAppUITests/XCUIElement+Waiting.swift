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

extension XCUIApplication {
    /// Scrolls the feed down until `element` is on screen, as someone would to reach an item below the first
    /// screenful: the feed only makes the cards it shows, so one further down isn't there to find until then. `false`
    /// if it never comes on screen.
    func scrollFeed(toShow element: XCUIElement, maxSwipes: Int = 6) -> Bool {
        for _ in 0 ..< maxSwipes {
            if element.exists, element.isHittable {
                return true
            }
            swipeUp(velocity: .slow)
        }
        return element.exists && element.isHittable
    }
}
