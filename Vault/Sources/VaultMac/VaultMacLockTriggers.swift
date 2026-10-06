import AppKit
import Foundation
import VaultFeed

/// Locks the Mac app when it should (docs/mac-app.md, "Locking").
///
/// - **At once, whatever the Require Unlock delay,** when the screen locks, the screen saver starts, the displays or
///   the Mac sleep, or the user switches to another account: the Mac's equivalents of iOS's
///   `protectedDataWillBecomeUnavailable`.
/// - **When another app comes to the front,** straight away or once the delay has passed with Vault still behind.
/// - **When the main window closes,** even with another of Vault's windows still open, so Vault never stays unlocked
///   without the window that shows it.
///
/// Coming back to the front starts unlocking by itself, as the iOS app does coming back to the foreground.
@MainActor
final class VaultMacLockTriggers {
    /// The distributed notifications that mean the Mac is locking: the screen locking, and the screen saver starting.
    nonisolated static let lockingDistributedNotifications = [
        Notification.Name("com.apple.screenIsLocked"),
        Notification.Name("com.apple.screensaver.didstart"),
    ]

    /// The workspace notifications that mean the Mac is locking: it sleeping, its displays sleeping, and another
    /// account taking over the screen.
    nonisolated static let lockingWorkspaceNotifications = [
        NSWorkspace.willSleepNotification,
        NSWorkspace.screensDidSleepNotification,
        NSWorkspace.sessionDidResignActiveNotification,
    ]

    private let appLock: AppLockService
    private let sleep: @Sendable (Duration) async throws -> Void
    private var observers = [(NotificationCenter, any NSObjectProtocol)]()
    /// Waits out the Require Unlock delay while another app is in front, then locks.
    private(set) var delayedLock: Task<Void, Never>?

    /// - Parameters:
    ///   - sleep: Waits for the Require Unlock delay. Tests make it return straight away.
    init(
        appLock: AppLockService,
        distributedCenter: NotificationCenter = DistributedNotificationCenter.default(),
        workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        applicationCenter: NotificationCenter = .default,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
    ) {
        self.appLock = appLock
        self.sleep = sleep
        for name in Self.lockingDistributedNotifications {
            observe(name, in: distributedCenter) { $0.deviceWillLock() }
        }
        for name in Self.lockingWorkspaceNotifications {
            observe(name, in: workspaceCenter) { $0.deviceWillLock() }
        }
        observe(NSApplication.didResignActiveNotification, in: applicationCenter) { $0.appDidLeave() }
        observe(NSWindow.willCloseNotification, in: applicationCenter) { triggers, notification in
            guard Self.isMainWindow(notification.object as? NSWindow) else { return }
            triggers.appLock.lockNow()
        }
        observe(NSApplication.didBecomeActiveNotification, in: applicationCenter) { $0.appDidReturn() }
    }

    isolated deinit {
        for (center, observer) in observers {
            center.removeObserver(observer)
        }
        delayedLock?.cancel()
    }

    private func observe(
        _ name: Notification.Name,
        in center: NotificationCenter,
        action: @escaping @MainActor (VaultMacLockTriggers) -> Void,
    ) {
        observe(name, in: center) { triggers, _ in action(triggers) }
    }

    private func observe(
        _ name: Notification.Name,
        in center: NotificationCenter,
        action: @escaping @MainActor (VaultMacLockTriggers, Notification) -> Void,
    ) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
            // Delivered on the main queue, where it's only read.
            nonisolated(unsafe) let notification = notification
            MainActor.assumeIsolated {
                guard let self else { return }
                action(self, notification)
            }
        }
        observers.append((center, observer))
    }

    /// Whether `window` is the main window: SwiftUI names it after its scene's ID.
    static func isMainWindow(_ window: NSWindow?) -> Bool {
        window?.identifier?.rawValue.hasPrefix(VaultMacWindow.main.id) == true
    }

    private func deviceWillLock() {
        delayedLock?.cancel()
        appLock.deviceWillLock()
    }

    /// Another app is in front: Vault locks now, or once the delay has passed while it's still behind.
    private func appDidLeave() {
        appLock.scenePhaseDidChange(to: .background)
        delayedLock?.cancel()
        guard appLock.isEnabled, !appLock.isLocked else { return }
        let delay = appLock.delay.duration
        delayedLock = Task { [weak self, sleep] in
            do {
                try await sleep(delay)
            } catch {
                return
            }
            self?.appLock.lockNow()
        }
    }

    /// Vault is in front again: it locks if it was behind for longer than the delay, and starts unlocking if it's
    /// locked.
    private func appDidReturn() {
        delayedLock?.cancel()
        delayedLock = nil
        appLock.scenePhaseDidChange(to: .active)
    }
}
