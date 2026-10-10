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
///
/// Vault's own Touch ID or password prompt isn't another app: macOS shows it from a process of its own, so Vault stops
/// being the active app while it's up, but the user hasn't left. Vault is only inactive then, as the iOS app is under
/// its own Face ID prompt. Taking it for leaving would lock Vault again behind the prompt, throw its answer away and
/// ask again, over and over. Another app coming to the front while the prompt is up is still leaving.
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
    private let authentication: DeviceAuthenticationService
    private let frontApplication: @MainActor () -> NSRunningApplication?
    private let sleep: @Sendable (Duration) async throws -> Void
    private var observers = [(NotificationCenter, any NSObjectProtocol)]()
    /// Waits out the Require Unlock delay while another app is in front, then locks.
    private(set) var delayedLock: Task<Void, Never>?
    /// Whether Vault stopped being the active app for its own Touch ID or password prompt, and hasn't been left since.
    private(set) var isBehindItsOwnPrompt = false

    /// - Parameters:
    ///   - authentication: Whose prompts are Vault's own.
    ///   - frontApplication: The app in front, as Vault stops being the active app.
    ///   - sleep: Waits for the Require Unlock delay. Tests make it return straight away.
    init(
        appLock: AppLockService,
        authentication: DeviceAuthenticationService,
        distributedCenter: NotificationCenter = DistributedNotificationCenter.default(),
        workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        applicationCenter: NotificationCenter = .default,
        frontApplication: @escaping @MainActor () -> NSRunningApplication? = VaultMacLockTriggers.frontmostApplication,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
    ) {
        self.appLock = appLock
        self.authentication = authentication
        self.frontApplication = frontApplication
        self.sleep = sleep
        for name in Self.lockingDistributedNotifications {
            observe(name, in: distributedCenter) { $0.deviceWillLock() }
        }
        for name in Self.lockingWorkspaceNotifications {
            observe(name, in: workspaceCenter) { $0.deviceWillLock() }
        }
        observe(NSWorkspace.didActivateApplicationNotification, in: workspaceCenter) { triggers, notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            triggers.applicationDidActivate(application)
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

    /// The app in front, as macOS tells it.
    static func frontmostApplication() -> NSRunningApplication? {
        NSWorkspace.shared.frontmostApplication
    }

    /// Whether `application` coming to the front means the user left Vault: it's an ordinary app, with a Dock icon and
    /// windows of its own, other than Vault. The agents that show Touch ID and the Mac's password aren't.
    static func isAnotherApp(_ application: NSRunningApplication?) -> Bool {
        guard let application else { return false }
        return application.activationPolicy == .regular
            && application.processIdentifier != ProcessInfo.processInfo.processIdentifier
    }

    private func deviceWillLock() {
        delayedLock?.cancel()
        appLock.deviceWillLock()
    }

    /// Vault stopped being the active app: the user left it, unless Vault's own prompt is in front.
    private func appDidLeave() {
        if authentication.isAuthenticating, !Self.isAnotherApp(frontApplication()) {
            isBehindItsOwnPrompt = true
            appLock.scenePhaseDidChange(to: .inactive)
            return
        }
        userDidLeave()
    }

    /// Another app coming to the front while Vault is behind its own prompt is the user leaving.
    private func applicationDidActivate(_ application: NSRunningApplication?) {
        guard isBehindItsOwnPrompt, Self.isAnotherApp(application) else { return }
        userDidLeave()
    }

    /// Another app is in front: Vault locks now, or once the delay has passed while it's still behind.
    private func userDidLeave() {
        isBehindItsOwnPrompt = false
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
        isBehindItsOwnPrompt = false
        delayedLock?.cancel()
        delayedLock = nil
        appLock.scenePhaseDidChange(to: .active)
    }
}
