import AppKit
import Foundation

/// Tells the AutoFill sheet when to lock: when the Mac locks, sleeps or its screen saver starts, as the app locks
/// (G29, G86), and when the user leaves the app the sheet is for, as the app locks when another comes to the front.
///
/// The sheet's own Touch ID or password prompt comes to the front from a process of its own, which isn't the user
/// leaving, as for the app (`VaultMacLockTriggers`): while it's up, only an ordinary app coming to the front is.
@MainActor
final class VaultMacAutofillLockObserver {
    private var observers: [(NotificationCenter, any NSObjectProtocol)] = []

    /// - Parameters:
    ///   - hostProcess: The app the sheet is filling a code for: another app coming to the front means the user left.
    ///   - isAuthenticating: Whether the sheet's own Touch ID or password prompt is up.
    ///   - macWillLock: Called as the Mac locks.
    ///   - userDidLeave: Called as another app comes to the front.
    init(
        hostProcess: pid_t?,
        isAuthenticating: @escaping @MainActor () -> Bool,
        distributedCenter: NotificationCenter = DistributedNotificationCenter.default(),
        workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        macWillLock: @escaping @MainActor () -> Void,
        userDidLeave: @escaping @MainActor () -> Void,
    ) {
        for name in VaultMacLockTriggers.lockingDistributedNotifications {
            observe(name, in: distributedCenter) { _ in macWillLock() }
        }
        for name in VaultMacLockTriggers.lockingWorkspaceNotifications {
            observe(name, in: workspaceCenter) { _ in macWillLock() }
        }
        observe(NSWorkspace.didActivateApplicationNotification, in: workspaceCenter) { activated in
            guard let activated, activated.processIdentifier != hostProcess else { return }
            if isAuthenticating(), !VaultMacLockTriggers.isAnotherApp(activated) {
                return
            }
            userDidLeave()
        }
    }

    /// Stops observing.
    func stop() {
        for (center, observer) in observers {
            center.removeObserver(observer)
        }
        observers = []
    }

    private func observe(
        _ name: Notification.Name,
        in center: NotificationCenter,
        action: @escaping @MainActor (NSRunningApplication?) -> Void,
    ) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                action(application)
            }
        }
        observers.append((center, observer))
    }
}
