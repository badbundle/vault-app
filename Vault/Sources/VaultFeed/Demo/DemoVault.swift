#if DEBUG
import Foundation
import VaultCore

/// The demo vault the App Store screenshots show, on the iPhone, the iPad and the Mac (`ScreenshotMode` in VaultiOS,
/// `VaultMacScreenshotMode` in VaultMac): tags, codes and notes made up for them, and four items that only a search for
/// `hiddenItemsPassphrase` shows. Compiled out of release builds.
public enum DemoVault {
    /// The search passphrase that shows the demo vault's hidden items.
    public static let hiddenItemsPassphrase = "blue heron"

    /// How far to move the app's clock so that, as the app launches, every demo code is `codeSecondsElapsed` into its
    /// period (the default 30 seconds). The screenshots are captured about 5 seconds after launch, so the countdowns
    /// show roughly 70% left in every shot, rather than wherever the real time happened to fall, and no shot catches a
    /// nearly empty one. The codes are still the right ones for the clock's time.
    public static func clockOffset(now: Double = Date.now.timeIntervalSince1970) -> Double {
        let period = Double(OTPAuthType.TOTP.defaultPeriod)
        let codeSecondsElapsed = 3.0
        let elapsed = now.truncatingRemainder(dividingBy: period)
        return (codeSecondsElapsed - elapsed + period).truncatingRemainder(dividingBy: period)
    }

    /// Fills `store` with the demo vault, records a PDF backup of it made at `backupDate`, and reloads `dataModel`
    /// from it.
    ///
    /// - Returns: The identifier of the first item, which the screenshots open.
    @MainActor
    public static func seed(
        store: some VaultStore & VaultTagStore,
        dataModel: VaultDataModel,
        backupEventLogger: any BackupEventLogger,
        backupDate: Date,
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
            backupDate: backupDate,
            hash: .makeHash(payload),
            vaultToken: backupEventLogger.vaultToken,
        )

        await dataModel.reloadTags()
        await dataModel.reloadItems()

        // `items` is non-empty, so the first insert always sets this.
        return detailItemID.unsafelyUnwrapped
    }

    public enum SeedingError: Error {
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

/// The demo vault's backup password: one is set, as far as Backups can tell, but there's no key to hand out, so
/// exporting finds none, and the keychain's is never read.
public final class DemoBackupPasswordStore: BackupPasswordStore {
    public let metadata: BackupPasswordMetadata

    public init(metadata: BackupPasswordMetadata) {
        self.metadata = metadata
    }

    public func fetchPassword() async throws -> DerivedEncryptionKey? {
        nil
    }

    public func set(password _: DerivedEncryptionKey) async throws {}

    public func upgradePassword(from _: DerivedEncryptionKey, to _: DerivedEncryptionKey) async throws {}

    public func removePassword() async throws {}

    public func fetchPasswordMetadata() async throws -> BackupPasswordMetadata? {
        metadata
    }
}
#endif
