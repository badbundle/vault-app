#if DEBUG
import Foundation
import UIKit
import VaultFeed
import VaultKeygen

/// Launch-argument driven demo state for marketing screenshots.
///
/// `make screenshots` (run from `Vault/`) launches a debug build with
/// `-screenshot-scene <scene>`. When that argument is present the composition
/// root swaps the on-disk vault for an empty in-memory one, so the simulator's
/// real vault is never read or written, seeds it with the demo vault below and
/// opens the app on the requested scene. Face ID always passes, as on an iPhone
/// with a passcode, and the scenes that show the App Lock Password have one,
/// kept by a stand-in for its storage: the demo vault stays in memory,
/// unencrypted. Compiled out of release builds.
enum ScreenshotMode {
    /// A screen the app can be launched straight into for a screenshot.
    ///
    /// The raw values are the names `Screenshots/capture.sh` passes on the
    /// command line.
    enum Scene: String, CaseIterable {
        /// The item feed.
        case feed
        /// The feed with the detail sheet open on the first demo item.
        case detail
        /// The feed searching for `hiddenItemsPassphrase`, which shows the hidden items.
        case search
        /// The first demo item's editor on its privacy and security step, part way through hiding the item, locking
        /// it and giving it a killphrase.
        case editor
        /// The lock screen, asking for the App Lock Password.
        case lock
        /// Settings with the App Lock Password's sheet open.
        case appLockPassword = "app-lock-password"
        /// The backups hub.
        case backups
        /// The settings screen, with App Lock and the App Lock Password on.
        case settings

        var sidebarItem: VaultMainNavigationView.SidebarItem {
            switch self {
            case .feed, .detail, .search, .editor, .lock: .items
            case .backups: .backups
            case .appLockPassword, .settings: .settings
            }
        }

        /// Whether the App Lock Password is set, so the app starts locked and asks for it after Face ID.
        var hasAppLockPassword: Bool {
            switch self {
            case .lock, .appLockPassword, .settings: true
            case .feed, .detail, .search, .editor, .backups: false
            }
        }

        /// Whether the password is entered for the scene as it's asked for, to show what's behind the lock screen.
        var entersAppLockPassword: Bool {
            hasAppLockPassword && self != .lock
        }
    }

    static let launchArgument = "-screenshot-scene"

    /// The scene named on the command line, or `nil` for a normal launch.
    ///
    /// A name that isn't a `Scene` is a bug in the capture script rather than a
    /// user error, so it fails loudly instead of silently screenshotting the
    /// simulator's real vault.
    static let scene: Scene? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: launchArgument) else { return nil }
        let name = arguments.dropFirst(index + 1).first ?? ""
        guard let scene = Scene(rawValue: name) else {
            let known = Scene.allCases.map(\.rawValue).joined(separator: ", ")
            fatalError("Unknown \(launchArgument) '\(name)'. Expected one of: \(known)")
        }
        return scene
    }()

    static var isEnabled: Bool {
        scene != nil
    }

    /// The App Lock Password of the scenes that have one.
    static let appLockPassword = "correct horse battery"

    /// The search passphrase that shows the demo vault's hidden items. The `editor` scene is typing it in too.
    static let hiddenItemsPassphrase = DemoVault.hiddenItemsPassphrase

    /// What the `editor` scene is typing in as a killphrase.
    static let editorKillphrase = "paper lantern"

    /// Face ID passes, as on an iPhone with a passcode. The simulator has none, and without one the lock screen,
    /// Settings and Restore say to set one up. `nil` for a normal launch.
    static var authenticationPolicy: (any DeviceAuthenticationPolicy)? {
        isEnabled ? UITestAuthenticationPolicy(answers: [.allow]) : nil
    }

    /// Stands in for the App Lock Password's storage in the scenes that have the password: it's set, with erasing
    /// after failed passwords on, and `appLockPassword` opens the vault. `nil` for every other scene.
    @MainActor
    static func makeAppLockPasswordService() -> (any AppLockPasswordService)? {
        guard scene?.hasAppLockPassword == true else { return nil }
        return FakeAppLockPasswordService(password: appLockPassword, erasesAfterFailedPasswords: true)
    }

    /// Enters the App Lock Password when the lock screen asks for it, in a scene that shows what's behind it.
    @MainActor
    static func enterAppLockPasswordIfAsked(_ state: AppLockState, appLock: AppLockService) {
        guard scene?.entersAppLockPassword == true, case let .locked(locked) = state, locked.step == .password,
              !locked.isInProgress, locked.failure == nil
        else { return }
        Task {
            await appLock.unlock(password: appLockPassword)
        }
    }

    /// Opens the `editor` scene's editor on its privacy and security step, with the code being hidden behind
    /// `hiddenItemsPassphrase`, locked and given a killphrase, but not yet saved.
    @MainActor
    static func showEditorScene(in viewModel: OTPCodeDetailViewModel) {
        viewModel.startEditing()
        viewModel.showEditorStep(.security)
        viewModel.editingModel.detail.viewConfig = .requiresSearchPassphrase
        viewModel.editingModel.detail.searchPassphrase = hiddenItemsPassphrase
        // QuickType never offers a hidden code.
        viewModel.editingModel.detail.showInQuickType = false
        viewModel.editingModel.detail.lockState = .lockedWithNativeSecurity
        viewModel.editingModel.detail.killphraseEnabled = true
        viewModel.editingModel.detail.newKillphrase = editorKillphrase
        scrollEditorSheetToEndOnIPad()
    }

    /// On iPad, scrolls the `editor` scene's sheet to the end of the step, which is taller than the sheet, so the
    /// killphrase shows. A form has no way to start scrolled to its end, so this finds the sheet's scroll view once
    /// it's on screen. The sheet takes a moment to come up and lay the step out, so it keeps scrolling for a few
    /// seconds, well within the capture's wait.
    @MainActor
    private static func scrollEditorSheetToEndOnIPad() {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        Task {
            for _ in 0 ..< 8 {
                try? await Task.sleep(for: .milliseconds(500))
                scrollPresentedSheetsToEnd()
            }
        }
    }

    @MainActor
    private static func scrollPresentedSheetsToEnd() {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        for window in windows {
            var controller = window.rootViewController
            while let presented = controller?.presentedViewController {
                controller = presented
            }
            guard controller !== window.rootViewController, let view = controller?.view,
                  let scrollView = firstScrollView(in: view)
            else { continue }
            let insets = scrollView.adjustedContentInset
            let end = scrollView.contentSize.height + insets.bottom - scrollView.bounds.height
            scrollView.setContentOffset(CGPoint(x: 0, y: max(end, -insets.top)), animated: false)
        }
    }

    @MainActor
    private static func firstScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView, scrollView.contentSize.height > scrollView.bounds.height {
            return scrollView
        }
        return view.subviews.lazy.compactMap(firstScrollView(in:)).first
    }

    /// Settings in a suite of their own, wiped on every launch, so nothing
    /// carries over between captures or into the standard defaults.
    @MainActor
    static func makeDefaults() -> Defaults {
        let suiteName = "com.badbundle.vault.screenshots"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create screenshot defaults suite")
        }
        userDefaults.removePersistentDomain(forName: suiteName)
        return Defaults(userDefaults: userDefaults)
    }

    /// The app lock's settings, likewise wiped on every launch: the lock is on only in the scenes with the App Lock
    /// Password.
    static func makeAppLockSettingsStore() -> AppLockSettingsStore {
        let suiteName = "com.badbundle.vault.screenshots.app-lock"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create screenshot app lock defaults suite")
        }
        userDefaults.removePersistentDomain(forName: suiteName)
        let settings = AppLockSettingsStore(userDefaults: userDefaults)
        settings.isEnabled = scene?.hasAppLockPassword == true
        return settings
    }

    /// Stands in for the keychain's backup password, which screenshots never read: the demo vault has one, set two
    /// weeks before its last backup.
    static let backupPasswordStore = DemoBackupPasswordStore(metadata: .init(
        lastSetDate: Calendar.current.date(byAdding: .day, value: -14, to: statusBarTimeToday),
    ))

    /// 9:41 today, the time `capture.sh` sets the status bar to: when the demo vault was last backed up.
    private static var statusBarTimeToday: Date {
        Calendar.current.date(bySettingHour: 9, minute: 41, second: 0, of: Date()) ?? Date()
    }

    /// Fills `store` with the demo vault (`DemoVault`), last backed up at 9:41 today, and reloads `dataModel` from it.
    ///
    /// - Returns: The identifier of the item the `detail` scene opens.
    @MainActor
    static func seed(
        store: some VaultStore & VaultTagStore,
        dataModel: VaultDataModel,
        backupEventLogger: any BackupEventLogger,
    ) async throws -> Identifier<VaultItem> {
        try await DemoVault.seed(
            store: store,
            dataModel: dataModel,
            backupEventLogger: backupEventLogger,
            backupDate: statusBarTimeToday,
        )
    }
}
#endif
