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
    static let hiddenItemsPassphrase = "blue heron"

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
    static let backupPasswordStore = ScreenshotBackupPasswordStore(metadata: .init(
        lastSetDate: Calendar.current.date(byAdding: .day, value: -14, to: statusBarTimeToday),
    ))

    /// 9:41 today, the time `capture.sh` sets the status bar to: when the demo vault was last backed up.
    private static var statusBarTimeToday: Date {
        Calendar.current.date(bySettingHour: 9, minute: 41, second: 0, of: Date()) ?? Date()
    }

    /// Fills `store` with the demo vault, records a fresh PDF backup of it
    /// and reloads `dataModel` from it.
    ///
    /// - Returns: The identifier of the item the `detail` scene opens.
    @MainActor
    static func seed(
        store: some VaultStore & VaultTagStore,
        dataModel: VaultDataModel,
        backupEventLogger: any BackupEventLogger,
    ) async throws -> Identifier<VaultItem> {
        let work = try await store.insertTag(item: .init(
            name: "Work",
            color: .init(red: 0.20, green: 0.47, blue: 0.96),
            iconName: "briefcase.fill",
        ))
        let personal = try await store.insertTag(item: .init(
            name: "Personal",
            color: .init(red: 0.20, green: 0.72, blue: 0.45),
            iconName: "person.fill",
        ))
        let finance = try await store.insertTag(item: .init(
            name: "Finance",
            color: .init(red: 0.96, green: 0.58, blue: 0.16),
            iconName: "creditcard.fill",
        ))
        let travel = try await store.insertTag(item: .init(
            name: "Travel",
            color: .init(red: 0.62, green: 0.40, blue: 0.93),
            iconName: "airplane",
        ))

        let items: [VaultItem.Write] = try [
            totp(
                .init(
                    issuer: "GitHub",
                    name: "bradley@example.com",
                    secret: "JBSWY3DPEHPK3PXP",
                    description: "Sign-in code for the badbundle org.",
                ),
                color: .init(red: 0.55, green: 0.36, blue: 0.96),
                tags: [work],
            ),
            totp(
                .init(issuer: "Google", name: "b.mackey@example.com", secret: "GEZDGNBVGY3TQOJQ"),
                color: .init(red: 0.26, green: 0.52, blue: 0.96),
                tags: [personal],
            ),
            totp(
                .init(issuer: "Monzo", name: "Current account", secret: "KRSXG5CTMVRXEZLU"),
                color: .init(red: 0.93, green: 0.36, blue: 0.42),
                tags: [finance],
                lockState: .lockedWithNativeSecurity,
            ),
            note(
                .init(
                    title: "Home Wi-Fi",
                    contents: "Network: Mackey-5G\nPassword: correct-horse-battery-staple",
                    format: .markdown,
                ),
                description: "Guest network details for visitors.",
                color: .init(red: 0.20, green: 0.72, blue: 0.45),
                tags: [personal],
            ),
            totp(
                .init(issuer: "Cloudflare", name: "ops@badbundle.com", secret: "MFRGGZDFMZTWQ2LK"),
                color: .init(red: 0.96, green: 0.50, blue: 0.20),
                tags: [work],
            ),
            encryptedNote(title: "Recovery codes", tags: [work]),
            note(
                .init(
                    title: "Passport",
                    contents: "Number: 123456789\nExpires: 14 March 2031\nIssued: HM Passport Office",
                    format: .markdown,
                ),
                description: "Renew six months before it expires.",
                color: .init(red: 0.62, green: 0.40, blue: 0.93),
                tags: [travel],
                previewMode: .titleOnly,
            ),
            hotp(
                .init(issuer: "Legacy VPN", name: "bmackey", secret: "ONSWG4TFOQQGC3DM"),
                color: .init(red: 0.45, green: 0.45, blue: 0.50),
                tags: [work],
            ),
            totp(
                .init(issuer: "Dropbox", name: "bradley@example.com", secret: "NBSWY3DPEB3W64TM"),
                color: .init(red: 0.00, green: 0.38, blue: 1.00),
                tags: [personal],
            ),
            totp(
                .init(issuer: "Slack", name: "badbundle.slack.com", secret: "MZXW6YTBOI2GK3TU"),
                color: .init(red: 0.88, green: 0.20, blue: 0.40),
                tags: [work],
            ),
            totp(
                .init(issuer: "Stripe", name: "badbundle.com", secret: "ON2HE2LQMU2GC3TE"),
                color: .init(red: 0.39, green: 0.34, blue: 0.96),
                tags: [work, finance],
            ),
            note(
                .init(
                    title: "Office door",
                    contents: "Front door: 4471#\nServer room: 9020#",
                    format: .markdown,
                ),
                description: "Codes change on the first of the month.",
                color: .init(red: 0.20, green: 0.47, blue: 0.96),
                tags: [work],
            ),
            totp(
                .init(issuer: "Amazon", name: "bradley@example.com", secret: "MFWWC6TPNYQGC3TE"),
                color: .init(red: 1.00, green: 0.60, blue: 0.00),
                tags: [personal],
            ),
            totp(
                .init(issuer: "AWS", name: "root (badbundle)", secret: "MF3XGIDSN5XXIIDB"),
                color: .init(red: 0.93, green: 0.55, blue: 0.14),
                tags: [work],
                lockState: .lockedWithNativeSecurity,
            ),
            totp(
                .init(issuer: "Airbnb", name: "bradley@example.com", secret: "MFUXEYTOMIQGC3TE"),
                color: .init(red: 1.00, green: 0.35, blue: 0.37),
                tags: [travel],
            ),
            totp(
                .init(issuer: "Steam", name: "bmackey", secret: "ON2GKYLNEBQWG3TU"),
                color: .init(red: 0.10, green: 0.16, blue: 0.24),
                tags: [personal],
            ),
        ]

        // Only a search for `hiddenItemsPassphrase` shows these, so they're never in the feed.
        await dataModel.loadSearchPassphraseDigester()
        guard let passphraseDigester = dataModel.searchPassphraseDigester else {
            throw SeedingError.noSearchPassphraseKey
        }
        let hiddenItems: [VaultItem.Write] = try [
            totp(
                .init(issuer: "Proton Mail", name: "b.mackey@proton.me", secret: "OBZG65DPNZWWC2LM"),
                color: .init(red: 0.43, green: 0.29, blue: 1.00),
                tags: [personal],
            ),
            note(
                .init(
                    title: "Journal",
                    contents: "Started again after the move.\nMostly lists, some days more.",
                    format: .markdown,
                ),
                description: "Notes to myself, most days.",
                color: .init(red: 0.93, green: 0.36, blue: 0.42),
                tags: [personal],
            ),
            totp(
                .init(issuer: "Kraken", name: "bradley@example.com", secret: "NNZGC23FNZWG6Z3T"),
                color: .init(red: 0.20, green: 0.72, blue: 0.45),
                tags: [finance],
            ),
            note(
                .init(title: "Safe", contents: "Left 32, right 18, left 4", format: .markdown),
                description: "The combination for the one at home.",
                color: .init(red: 0.96, green: 0.58, blue: 0.16),
                tags: [finance],
            ),
        ].map { item in
            var item = item
            item.visibility = .onlySearch
            item.searchableLevel = .onlyPassphrase
            item.searchPassphraseUpdate = .set(passphraseDigester.makeDigest(phrase: hiddenItemsPassphrase))
            // QuickType never offers a hidden code.
            item.showInQuickType = false
            return item
        }

        var detailItemID: Identifier<VaultItem>?
        for (index, var item) in (items + hiddenItems).enumerated() {
            item.relativeOrder = UInt64(index)
            let id = try await store.insert(item: item)
            detailItemID = detailItemID ?? id
        }

        // The backups hub otherwise opens on a "no backups" warning.
        let payload = try await store.exportVault(userDescription: "")
        try backupEventLogger.exportedToPDF(
            backupDate: statusBarTimeToday,
            hash: .makeHash(payload),
            vaultToken: backupEventLogger.vaultToken,
        )

        await dataModel.reloadTags()
        await dataModel.reloadItems()

        // `items` is non-empty, so the first insert always sets this.
        return detailItemID.unsafelyUnwrapped
    }

    enum SeedingError: Error {
        /// The search passphrase's key couldn't be read or made, so the hidden items couldn't be hidden.
        case noSearchPassphraseKey
    }

    /// Who a demo OTP code belongs to. `secret` is base32; `description` is
    /// the item's user description, shown on the detail screen.
    private struct Account {
        var issuer: String
        var name: String
        var secret: String
        var description: String?
    }

    private static func totp(
        _ account: Account,
        color: VaultItemColor,
        tags: Set<Identifier<VaultItemTag>>,
        lockState: VaultItemLockState = .notLocked,
    ) throws -> VaultItem.Write {
        try otp(type: .totp(), account: account, color: color, tags: tags, lockState: lockState)
    }

    private static func hotp(
        _ account: Account,
        color: VaultItemColor,
        tags: Set<Identifier<VaultItemTag>>,
    ) throws -> VaultItem.Write {
        try otp(type: .hotp(counter: 42), account: account, color: color, tags: tags, lockState: .notLocked)
    }

    private static func otp(
        type: OTPAuthType,
        account: Account,
        color: VaultItemColor,
        tags: Set<Identifier<VaultItemTag>>,
        lockState: VaultItemLockState,
    ) throws -> VaultItem.Write {
        let code = try OTPAuthCode(
            type: type,
            data: .init(
                secret: .base32EncodedString(account.secret),
                accountName: account.name,
                issuer: account.issuer,
            ),
        )
        return .init(
            relativeOrder: 0,
            userDescription: account.description ?? account.issuer,
            color: color,
            item: .otpCode(code),
            tags: tags,
            visibility: .always,
            searchableLevel: .full,
            searchPassphraseUpdate: .clear,
            killphraseUpdate: .clear,
            lockState: lockState,
            showInQuickType: true,
            previewMode: .titleAndFirstLine,
        )
    }

    /// `description` is the feed card's secondary line (hidden by `.titleOnly`).
    private static func note(
        _ note: SecureNote,
        description: String,
        color: VaultItemColor,
        tags: Set<Identifier<VaultItemTag>>,
        previewMode: NotePreviewMode = .titleAndFirstLine,
    ) -> VaultItem.Write {
        .init(
            relativeOrder: 0,
            userDescription: description,
            color: color,
            item: .secureNote(note),
            tags: tags,
            visibility: .always,
            searchableLevel: .full,
            searchPassphraseUpdate: .clear,
            killphraseUpdate: .clear,
            lockState: .notLocked,
            showInQuickType: false,
            previewMode: previewMode,
        )
    }

    /// The payload is the developer-tools demo note (password "hello"); only
    /// the container's plaintext title shows in the feed.
    private static func encryptedNote(title: String, tags: Set<Identifier<VaultItemTag>>) throws -> VaultItem.Write {
        // Encrypted with the title rather than renaming it afterwards, so the
        // plaintext title matches the encrypted one, as it does in the app.
        var item = try VaultItemDemoFactory().makeEncryptedSecureNote(title: title)
        item.userDescription = title
        item.tags = tags
        return item
    }
}

/// The backup password in screenshot mode: one is set, as far as Backups can tell, but there's no key to hand out, so
/// exporting finds none.
final class ScreenshotBackupPasswordStore: BackupPasswordStore {
    let metadata: BackupPasswordMetadata

    init(metadata: BackupPasswordMetadata) {
        self.metadata = metadata
    }

    func fetchPassword() async throws -> DerivedEncryptionKey? {
        nil
    }

    func set(password _: DerivedEncryptionKey) async throws {}

    func removePassword() async throws {}

    func fetchPasswordMetadata() async throws -> BackupPasswordMetadata? {
        metadata
    }
}
#endif
