import AppKit
import Foundation

/// What means the Mac is locking, and which app coming to the front means the user left Vault: the same for the app's
/// `VaultMacLockTriggers` and the AutoFill extension's lock observer.
public enum VaultMacLockingEvents {
    /// The distributed notifications that mean the Mac is locking: the screen locking, and the screen saver starting.
    public static let distributedNotifications = [
        Notification.Name("com.apple.screenIsLocked"),
        Notification.Name("com.apple.screensaver.didstart"),
    ]

    /// The workspace notifications that mean the Mac is locking: it sleeping, its displays sleeping, and another
    /// account taking over the screen.
    public static let workspaceNotifications = [
        NSWorkspace.willSleepNotification,
        NSWorkspace.screensDidSleepNotification,
        NSWorkspace.sessionDidResignActiveNotification,
    ]

    /// Whether `application` coming to the front means the user left Vault: it's an ordinary app, with a Dock icon and
    /// windows of its own, other than Vault. The agents that show Touch ID and the Mac's password aren't.
    @MainActor
    public static func isAnotherApp(_ application: NSRunningApplication?) -> Bool {
        guard let application else { return false }
        return application.activationPolicy == .regular
            && application.processIdentifier != ProcessInfo.processInfo.processIdentifier
    }
}
