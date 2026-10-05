import AppKit
import Foundation

/// Tells the AutoFill sheet when to lock: when the Mac locks, sleeps or its screen saver starts, as the app locks
/// (G29, G86), and when the user leaves the app the sheet is for, as the app locks when another comes to the front.
@MainActor
final class VaultMacAutofillLockObserver {
    private var observers: [(NotificationCenter, any NSObjectProtocol)] = []

    /// - Parameters:
    ///   - hostProcess: The app the sheet is filling a code for: another app coming to the front means the user left.
    ///   - macWillLock: Called as the Mac locks.
    ///   - userDidLeave: Called as another app comes to the front.
    init(
        hostProcess: pid_t?,
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
            guard let activated, activated != hostProcess else { return }
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
        action: @escaping @MainActor (pid_t?) -> Void,
    ) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let process = application?.processIdentifier
            MainActor.assumeIsolated {
                action(process)
            }
        }
        observers.append((center, observer))
    }
}
