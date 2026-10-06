import AppKit

/// The Mac app's delegate: Vault quits once its last window closes, as a single-window Mac app does. Every launch
/// starts locked, so closing the window locks Vault too.
@MainActor
public final class VaultMacAppDelegate: NSObject, NSApplicationDelegate {
    override public init() {
        super.init()
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }

    /// Clears what Vault copied, if it's still on the clipboard: quitting ends the timer that would have (G50).
    public func applicationWillTerminate(_: Notification) {
        VaultMacRoot.pasteboard.clearNow()
    }
}
