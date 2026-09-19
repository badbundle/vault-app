#if DEBUG
import Foundation
import VaultFeed

/// Launch-argument driven demo state for marketing screenshots.
///
/// `make screenshots` (run from `Vault/`) launches a debug build with
/// `-screenshot-scene <scene>`. When that argument is present the composition
/// root swaps the on-disk vault for an empty in-memory one, so the simulator's
/// real vault is never read or written, seeds it with the demo vault below and
/// opens the app on the requested scene. Compiled out of release builds.
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
        /// The tag list.
        case tags
        /// The backups hub.
        case backups
        /// The settings screen.
        case settings

        var sidebarItem: VaultMainNavigationView.SidebarItem {
            switch self {
            case .feed, .detail: .items
            case .tags: .tags
            case .backups: .backups
            case .settings: .settings
            }
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

    /// Fills `store` with the demo vault, records a fresh PDF backup of it
    /// and reloads `dataModel` from it.
    ///
    /// - Returns: The identifier of the item the `detail` scene opens.
    @MainActor
    static func seed(
        store: PersistedLocalVaultStore,
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

        var detailItemID: Identifier<VaultItem>?
        for (index, var item) in items.enumerated() {
            item.relativeOrder = UInt64(index)
            let id = try await store.insert(item: item)
            detailItemID = detailItemID ?? id
        }

        // The backups hub otherwise opens on a "no backups" warning.
        let payload = try await store.exportVault(userDescription: "")
        try backupEventLogger.exportedToPDF(date: Date(), hash: .makeHash(payload))

        await dataModel.reloadTags()
        await dataModel.reloadItems()

        // `items` is non-empty, so the first insert always sets this.
        return detailItemID.unsafelyUnwrapped
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
        var item = try VaultItemDemoFactory().makeEncryptedSecureNote()
        guard case var .encryptedItem(encrypted) = item.item else {
            fatalError("makeEncryptedSecureNote() should produce an encrypted item")
        }
        encrypted.title = title
        item.item = .encryptedItem(encrypted)
        item.userDescription = title
        item.tags = tags
        return item
    }
}
#endif
