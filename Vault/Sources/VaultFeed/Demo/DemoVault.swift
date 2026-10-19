#if DEBUG
import CryptoKit
import Foundation
import VaultCore

/// The demo vault the App Store screenshots show, on the iPhone, the iPad and the Mac (`ScreenshotMode` in VaultiOS,
/// `VaultMacScreenshotMode` in VaultMac): recovery phrases and private keys first, then notes and codes, with tags, all
/// made up for them, and three items that only a search for `hiddenItemsPassphrase` shows. Compiled out of release
/// builds.
///
/// As in the app, every recovery phrase and private key is an encrypted item with a password of its own
/// (`encryptedItemPassword`), so the feed shows only its title, and its page opens locked.
public enum DemoVault {
    /// The search passphrase that shows the demo vault's hidden items.
    public static let hiddenItemsPassphrase = "blue heron"

    /// The password of every demo item that's encrypted with one of its own: the recovery phrases, the private keys
    /// and the "Exchange 2FA backup codes" note.
    public static let encryptedItemPassword = "hello"

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

    /// The demo items the screenshot scenes open, once `seed` has put them in the vault. Each recovery phrase is
    /// decrypted, as its password opens it, with the key it was decrypted with.
    public struct SeededItems: Sendable {
        /// The first item, the "Cold storage" recovery phrase, of 24 words.
        public var firstItem: VaultItemEncryptionPayload
        /// The "Everyday wallet" recovery phrase, of 12 words, few enough that its editor shows whether they're valid
        /// below them without scrolling.
        public var everydayWallet: VaultItemEncryptionPayload
        /// The first code, GitHub's.
        public var firstCodeID: Identifier<VaultItem>
    }

    /// Fills `store` with the demo vault, records a PDF backup of it made at `backupDate`, and reloads `dataModel`
    /// from it.
    @MainActor
    public static func seed(
        store: some VaultStore & VaultTagStore,
        dataModel: VaultDataModel,
        backupEventLogger: any BackupEventLogger,
        backupDate: Date,
    ) async throws -> SeededItems {
        let crypto = try await store.insertTag(item: .init(
            name: "Crypto",
            color: .init(red: 0.96, green: 0.58, blue: 0.16),
            iconName: "bitcoinsign.circle.fill",
        ))
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
            color: .init(red: 0.62, green: 0.40, blue: 0.93),
            iconName: "creditcard.fill",
        ))
        let travel = try await store.insertTag(item: .init(
            name: "Travel",
            color: .init(red: 0.93, green: 0.36, blue: 0.42),
            iconName: "airplane",
        ))

        // One key for every encrypted item, from a debug build's fast key derivation, so seeding stays quick.
        let key = try VaultKeyDeriver.Item.Fast.v2.createEncryptionKey(password: encryptedItemPassword)
        let items: [VaultItem.Write] = try [
            encrypted(coldStorage, key: key, color: .init(red: 0.96, green: 0.58, blue: 0.16), tags: [crypto]),
            encrypted(everydayWallet, key: key, color: .init(red: 0.20, green: 0.72, blue: 0.45), tags: [crypto]),
            encrypted(moneroWallet, key: key, color: .init(red: 0.93, green: 0.40, blue: 0.13), tags: [crypto]),
            encrypted(shamirShare, key: key, color: .init(red: 0.26, green: 0.52, blue: 0.96), tags: [crypto]),
            encrypted(extendedKey, key: key, color: .init(red: 0.55, green: 0.36, blue: 0.96), tags: [crypto]),
            encrypted(paperWalletKey, key: key, color: .init(red: 0.85, green: 0.65, blue: 0.13), tags: [crypto]),
            encrypted(
                makeServerSSHKey(),
                key: key,
                color: .init(red: 0.45, green: 0.45, blue: 0.50),
                tags: [work],
            ),
            note(
                .init(
                    title: "Hardware wallet PIN",
                    contents: "PIN: 4 8 1 5 9 2\nIt wipes itself after 16 wrong PINs.",
                    format: .markdown,
                ),
                description: "For the hardware wallet in the safe.",
                color: .init(red: 0.96, green: 0.58, blue: 0.16),
                tags: [crypto],
                lockState: .lockedWithNativeSecurity,
                previewMode: .titleOnly,
            ),
            encrypted(
                exchangeBackupCodes,
                key: key,
                color: .init(red: 0.62, green: 0.40, blue: 0.93),
                tags: [finance],
                lockState: .notLocked,
            ),
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
                .init(issuer: "Kraken", name: "bradley@example.com", secret: "NNZGC23FNZWG6Z3T"),
                color: .init(red: 0.43, green: 0.29, blue: 1.00),
                tags: [finance, crypto],
                lockState: .lockedWithNativeSecurity,
            ),
            totp(
                .init(issuer: "Cloudflare", name: "ops@badbundle.com", secret: "MFRGGZDFMZTWQ2LK"),
                color: .init(red: 0.96, green: 0.50, blue: 0.20),
                tags: [work],
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
            note(
                .init(
                    title: "Passport",
                    contents: "Number: 123456789\nExpires: 14 March 2031\nIssued: HM Passport Office",
                    format: .markdown,
                ),
                description: "Renew six months before it expires.",
                color: .init(red: 0.93, green: 0.36, blue: 0.42),
                tags: [travel],
                previewMode: .titleOnly,
            ),
        ]

        // Only a search for `hiddenItemsPassphrase` shows these, so they're never in the feed.
        await dataModel.loadSearchPassphraseDigester()
        guard let passphraseDigester = dataModel.searchPassphraseDigester else {
            throw SeedingError.noSearchPassphraseKey
        }
        let hiddenItems: [VaultItem.Write] = try [
            encrypted(savingsWallet, key: key, color: .init(red: 0.20, green: 0.47, blue: 0.96), tags: [crypto]),
            totp(
                .init(issuer: "Proton Mail", name: "b.mackey@proton.me", secret: "OBZG65DPNZWWC2LM"),
                color: .init(red: 0.43, green: 0.29, blue: 1.00),
                tags: [personal],
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

        var ids = [Identifier<VaultItem>]()
        for (index, var item) in (items + hiddenItems).enumerated() {
            item.relativeOrder = UInt64(index)
            let id = try await store.insert(item: item)
            ids.append(id)
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

        func decrypted(_ phrase: RecoveryPhrase, at index: Int) throws -> VaultItemEncryptionPayload {
            guard let item = dataModel.code(id: ids[index]) else { throw SeedingError.notSeeded }
            return .init(
                decryptedItem: VaultItem(metadata: item.metadata, item: .recoveryPhrase(phrase)),
                encryptionKey: key,
            )
        }
        guard let firstCodeIndex = items.firstIndex(where: \.isOTPCode) else { throw SeedingError.notSeeded }
        return try SeededItems(
            firstItem: decrypted(coldStorage, at: 0),
            everydayWallet: decrypted(everydayWallet, at: 1),
            firstCodeID: ids[firstCodeIndex],
        )
    }

    public enum SeedingError: Error {
        /// The search passphrase's key couldn't be read or made, so the hidden items couldn't be hidden.
        case noSearchPassphraseKey
        /// The items went in, but the data model didn't load them.
        case notSeeded
    }

    // MARK: - Recovery phrases and private keys

    // Generated for the screenshots from random bytes, with valid checksums, and checked against Vault's own word lists
    // (`DemoVaultTests`). They're demo-only: no wallet was ever made from them or funded, none is a published test
    // vector, and they mustn't be used for anything else. The SSH key is made afresh at every launch.

    /// BIP39, 24 words, with a passphrase.
    static let coldStorage = RecoveryPhrase(
        title: "Cold storage",
        words: words(
            "theme make host lamp convince trade nephew private accuse access candy inch meadow fire captain shaft change oyster since acquire milk giraffe opera blanket",
        ),
        standard: .bip39,
        passphrase: "harbour lights",
        contents: "The hardware wallet's backup. A steel copy is in the safe deposit box.",
    )

    /// BIP39, 12 words.
    static let everydayWallet = RecoveryPhrase(
        title: "Everyday wallet",
        words: words("injury during rhythm sister curious sail inform prevent example slim trade mystery"),
        standard: .bip39,
        passphrase: "",
        contents: "The wallet on my phone, for spending.",
    )

    /// Monero, 25 words: a spend key reduced as Monero makes them, and the checksum word.
    static let moneroWallet = RecoveryPhrase(
        title: "Monero wallet",
        words: words(
            "because pests ionic buckets begun tapestry uncle sickness leisure teardrop wise recipe lettuce pegs auburn pelican upbeat navy hockey pebbles syringe itself divers doing tapestry",
        ),
        standard: .monero,
        passphrase: "",
        contents: "Desktop wallet.",
    )

    /// SLIP-39, 20 words: the first member share of a 2 of 3 set, extendable.
    static let shamirShare = RecoveryPhrase(
        title: "Shamir share 1 of 3",
        words: words(
            "garlic vexed academic acid craft sprinkle credit timely spider rhyme cylinder garlic marvel diploma true similar mental building laden sprinkle",
        ),
        standard: .slip39,
        passphrase: "",
        contents: "Any 2 of the 3 shares restore the wallet.",
    )

    /// BIP39, 24 words, hidden behind `hiddenItemsPassphrase`.
    static let savingsWallet = RecoveryPhrase(
        title: "Savings wallet",
        words: words(
            "elevator amount firm balance candy silver wise spawn bicycle hen air sweet cinnamon bus column sauce order grit glad march match attitude success napkin",
        ),
        standard: .bip39,
        passphrase: "",
        contents: "Long-term savings. Never on a phone.",
    )

    /// A BIP32 master key (mainnet `xprv`): a random chain code and key.
    static let extendedKey = PrivateKey(
        title: "Bitcoin xprv",
        key: "xprv9s21ZrQH143K2exDfDohvQnf7oaE5EJUKJ2f8oL1Q2YdqMwLn957ZzNSt7FysT478arSsU8t33e8fe8wzTBxmMmGdmoWw4rLRWSEHvt6Nvy",
        contents: "Master key of the old desktop wallet.",
    )

    /// A WIF key (mainnet, compressed): a random key.
    static let paperWalletKey = PrivateKey(
        title: "Paper wallet key",
        key: "L55bxNWQ9f6AJf1QdGa1QimLmYAMPoYgiwK2xT7sKHvequTE4Wm1",
        contents: "From the paper wallet in the desk drawer.",
    )

    /// The demo vault's recovery phrases, the hidden one last.
    static var recoveryPhrases: [RecoveryPhrase] {
        [coldStorage, everydayWallet, moneroWallet, shamirShare, savingsWallet]
    }

    /// An OpenSSH Ed25519 key, as `ssh-keygen -t ed25519` writes one without a passphrase (PROTOCOL.key in OpenSSH),
    /// made afresh each time, so no private key is ever in the source. It's never used.
    static func makeServerSSHKey() -> PrivateKey {
        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKey = privateKey.publicKey.rawRepresentation
        let keyType = Data("ssh-ed25519".utf8)
        let comment = Data("deploy@build-server".utf8)

        var publicBlob = Data()
        publicBlob.appendSSHString(keyType)
        publicBlob.appendSSHString(publicKey)

        let checkInt = UInt32.random(in: .min ... .max)
        var privateSection = Data()
        privateSection.appendSSHUInt32(checkInt)
        privateSection.appendSSHUInt32(checkInt)
        privateSection.appendSSHString(keyType)
        privateSection.appendSSHString(publicKey)
        privateSection.appendSSHString(privateKey.rawRepresentation + publicKey)
        privateSection.appendSSHString(comment)
        // Padded to the "none" cipher's block size with 1, 2, 3 and so on.
        var padding: UInt8 = 1
        while !privateSection.count.isMultiple(of: 8) {
            privateSection.append(padding)
            padding += 1
        }

        var blob = Data("openssh-key-v1".utf8) + [0]
        blob.appendSSHString(Data("none".utf8)) // cipher
        blob.appendSSHString(Data("none".utf8)) // KDF
        blob.appendSSHString(Data()) // KDF options
        blob.appendSSHUInt32(1) // number of keys
        blob.appendSSHString(publicBlob)
        blob.appendSSHString(privateSection)

        let base64 = Array(blob.base64EncodedString())
        let lines = stride(from: 0, to: base64.count, by: 70).map { String(base64[$0 ..< min($0 + 70, base64.count)]) }
        let armored = (["-----BEGIN OPENSSH PRIVATE KEY-----"] + lines + ["-----END OPENSSH PRIVATE KEY-----"])
            .joined(separator: "\n")
        return PrivateKey(title: "Server SSH key", key: armored, contents: "Deploy key for the build server.")
    }

    /// Encrypted, as every one in the app is. As in the app, the title is the note's first line.
    static let exchangeBackupCodes = SecureNote(
        title: "Exchange 2FA backup codes",
        contents: "Exchange 2FA backup codes\n4F7K-29QX\n8MRT-3D6W\nQ2PH-71ZC\nX9LN-5B4V\nH3WD-K8JR",
        format: .plain,
    )

    private static func words(_ phrase: String) -> [String] {
        phrase.split(separator: " ").map(String.init)
    }

    /// Encrypted with `key`, as the app saves an item with a password of its own: nothing of it but its title is
    /// outside the encryption. A recovery phrase or a private key is always locked as well.
    private static func encrypted(
        _ item: some VaultItemEncryptable,
        key: DerivedEncryptionKey,
        color: VaultItemColor,
        tags: Set<Identifier<VaultItemTag>>,
        lockState: VaultItemLockState = .lockedWithNativeSecurity,
    ) throws -> VaultItem.Write {
        try .init(
            relativeOrder: 0,
            userDescription: "",
            color: color,
            item: .encryptedItem(VaultItemEncryptor(key: key).encrypt(item: item)),
            tags: tags,
            visibility: .always,
            searchableLevel: .full,
            searchPassphraseUpdate: .clear,
            killphraseUpdate: .clear,
            lockState: lockState,
            showInQuickType: false,
            previewMode: .titleOnly,
        )
    }

    // MARK: - Codes and notes

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
        let code = try OTPAuthCode(
            type: .totp(),
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
        lockState: VaultItemLockState = .notLocked,
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
            lockState: lockState,
            showInQuickType: false,
            previewMode: previewMode,
        )
    }
}

extension VaultItem.Write {
    fileprivate var isOTPCode: Bool {
        if case .otpCode = item {
            true
        } else {
            false
        }
    }
}

extension Data {
    /// An SSH wire format `string`: its length as a big-endian `uint32`, then its bytes.
    fileprivate mutating func appendSSHString(_ bytes: Data) {
        appendSSHUInt32(UInt32(bytes.count))
        append(bytes)
    }

    fileprivate mutating func appendSSHUInt32(_ value: UInt32) {
        append(contentsOf: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: value >> $0) })
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
