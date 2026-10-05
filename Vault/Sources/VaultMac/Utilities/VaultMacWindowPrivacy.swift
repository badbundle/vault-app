import AppKit
import VaultFeed
import VaultSettings

/// Keeps every window Vault opens private (docs/mac-app.md, "Hide While Recording" and "Other ways a window's contents
/// could leak"): the main window, Settings and About, and every sheet, alert and panel of Vault's own.
///
/// - With Hide While Recording on, the default, a window's `sharingType` is `.none`, so it's left out of screenshots,
///   screen recordings, screen sharing and AirPlay (G24). Turning it off gives the system's default, `.readOnly`.
/// - No window is restorable, so macOS never saves what one showed, and none can be a tab.
/// - Minimising a window locks Vault first, so the Dock shows only the lock screen.
@MainActor
final class VaultMacWindowPrivacy {
    private let localSettings: LocalSettings
    private let appLock: AppLockService
    private let center: NotificationCenter
    private var observers: [any NSObjectProtocol] = []

    init(localSettings: LocalSettings, appLock: AppLockService, center: NotificationCenter = .default) {
        self.localSettings = localSettings
        self.appLock = appLock
        self.center = center
    }

    /// The sharing type every window has while Hide While Recording says so.
    var sharingType: NSWindow.SharingType {
        localSettings.state.hidesVaultWhileScreenCaptured ? .none : .readOnly
    }

    /// Starts keeping every window private: those already open, and each one as it opens or changes.
    func start(windows: [NSWindow]) {
        for window in windows {
            apply(to: window)
        }
        // A window updates as it opens, and then each time it's drawn again, so a change to the setting reaches every
        // window at once, and so does a sheet or alert as soon as it appears.
        observers
            .append(center.addObserver(forName: NSWindow.didUpdateNotification, object: nil, queue: .main) { note in
                guard let window = note.object as? NSWindow else { return }
                MainActor.assumeIsolated { self.apply(to: window) }
            })
        observers.append(center.addObserver(
            forName: NSWindow.willMiniaturizeNotification,
            object: nil,
            queue: .main,
        ) { _ in
            MainActor.assumeIsolated { self.appLock.lockNow() }
        })
    }

    /// Makes `window` private, if it isn't already.
    func apply(to window: NSWindow) {
        let sharingType = sharingType
        if window.sharingType != sharingType {
            window.sharingType = sharingType
        }
        if window.isRestorable {
            window.isRestorable = false
        }
        if window.tabbingMode != .disallowed {
            window.tabbingMode = .disallowed
        }
    }
}
