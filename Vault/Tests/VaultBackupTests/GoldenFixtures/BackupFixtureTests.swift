import CryptoEngine
import Foundation
import FoundationExtensions
import Testing
import VaultCore
import VaultKeygen
@testable import VaultBackup

/// The backup fixtures: the same populated backup saved padded to a fixed size (VAULT-75), and padded by a random
/// amount as every backup was before that. See `Fixtures/README.md`.
struct BackupFixtureTests {
    @Test(arguments: BackupFixture.all)
    func encryptedVault_namesItsVersionDerivationAndSalt(fixture: BackupFixture) throws {
        let vault = try fixture.encryptedVault()

        #expect(vault.version == "1.0.0")
        #expect(vault.keygenSignature == VaultKeyDeriver.Signature.backupFastV1.rawValue)
        #expect(vault.keygenSalt.count == 48)
        #expect(vault.encryptionIV.count == 32)
        #expect(vault.authentication.count == 16)
        #expect(vault.data.count == fixture.encryptedLength)
    }

    @Test(arguments: BackupFixture.all)
    func decrypt_withThePassword_givesTheBackupItWasMadeFrom(fixture: BackupFixture) throws {
        let vault = try fixture.encryptedVault()

        let payload = try VaultBackupDecryptor(key: BackupFixture.key(for: vault).key).decryptBackupPayload(from: vault)

        #expect(payload.version == "1.0.0")
        #expect(payload.created == BackupFixture.created)
        #expect(payload.userDescription == BackupFixture.userDescription)
        #expect(payload.tags == BackupFixture.tags)
        #expect(payload.items == BackupFixture.items)
        #expect(fixture.paddingLengths.contains(payload.obfuscationPadding.count))
    }

    @Test(arguments: BackupFixture.all)
    func decrypt_withAWrongPassword_fails(fixture: BackupFixture) throws {
        let vault = try fixture.encryptedVault()
        let wrongKey = try VaultKeyDeriver.Backup.Fast.v1.recreateEncryptionKey(
            password: BackupFixture.password.uppercased(),
            salt: vault.keygenSalt,
        )

        let error = #expect(throws: VaultBackupDecryptor.Error.self) {
            try VaultBackupDecryptor(key: wrongKey.key).decryptBackupPayload(from: vault)
        }
        guard case .decryptionFailed = error else {
            Issue.record("Expected .decryptionFailed, got \(String(describing: error))")
            return
        }
    }

    /// A known answer for the encryptor: given the fixture's randomness (its salt, its IV and its padding), it writes
    /// exactly the fixture's bytes.
    ///
    /// Only the newest fixture of each kind of padding is also a known answer for the writer. When what's written
    /// changes, the check moves to the new fixture, and the old one keeps the reading tests.
    @Test(arguments: BackupFixture.all)
    func encrypt_withTheFixturesRandomness_writesExactlyTheFixture(fixture: BackupFixture) throws {
        let vault = try fixture.encryptedVault()
        let key = try BackupFixture.key(for: vault)
        let payload = try VaultBackupDecryptor(key: key.key).decryptBackupPayload(from: vault)
        let sut = try VaultBackupEncryptor(
            clock: EpochClockMock(currentTime: BackupFixture.created.timeIntervalSince1970),
            key: VaultKey(key: key.key, iv: KeyData(data: vault.encryptionIV)),
            keygenSalt: vault.keygenSalt,
            keygenSignature: vault.keygenSignature,
            paddingMode: .fixed(data: payload.obfuscationPadding),
        )

        let encrypted = try sut.encryptBackupPayload(
            items: BackupFixture.items,
            tags: BackupFixture.tags,
            userDescription: BackupFixture.userDescription,
        )

        #expect(encrypted == vault)
    }
}

// MARK: - Fixtures

/// A backup as the app saves it: the `EncryptedVault` a PDF or an auto-backup carries, as `EncryptedVaultCoder` encodes
/// it, before a PDF splits it into QR codes. Both fixtures hold the same backup of a vault with a few items.
///
/// The key is derived from the backup password with `vault.keygen.backup.fast.v1`, as debug builds of the app derive
/// it, which takes milliseconds. Release builds derive with `vault.keygen.backup.secure.v1`, which takes minutes
/// without
/// optimization: `VaultKeyDeriverParameterPinTests` pins its parameters, and `CryptoEngineTests` the derivations it
/// chains.
///
/// The items are as `VaultBackupItemEncoder` writes them from the app's items. Each has one tag at most: a set of tags
/// is written in no particular order, which would stop the encryptor's known answer from being known.
struct BackupFixture: Sendable, CustomTestStringConvertible {
    enum Padding: Sendable {
        /// To just under 32 KiB of ciphertext, as saved backups have been since VAULT-75.
        case toFixedSize
        /// By a random amount, as every backup was before VAULT-75, and a device transfer still is.
        case random
    }

    var name: String
    var padding: Padding
    /// The length of the ciphertext, recorded.
    var encryptedLength: Int

    var testDescription: String {
        name
    }

    /// How long the padding can be.
    var paddingLengths: Range<Int> {
        switch padding {
        // As much as the items leave of 32 KiB: they compress to a few hundred bytes.
        case .toFixedSize: 30000 ..< 32 * 1024
        // What `VaultBackupEncryptor` chooses for a vault of 1 to 9 items.
        case .random: 300 ..< 3300
        }
    }

    static let paddedToFixedSize = BackupFixture(
        name: "backup-v1-padded-to-32-kib.json",
        padding: .toFixedSize,
        encryptedLength: 32764,
    )

    static let paddedRandomly = BackupFixture(
        name: "backup-v1-random-padding.json",
        padding: .random,
        encryptedLength: 2420,
    )

    static let all = [paddedToFixedSize, paddedRandomly]

    /// The backup, read from the test bundle.
    func encryptedVault() throws -> EncryptedVault {
        try EncryptedVaultCoder().decode(vaultData: GoldenFixture.data(named: name))
    }

    /// Derives the key from the password as restoring a backup does, with the salt and the derivation the backup names.
    static func key(for vault: EncryptedVault) throws -> DerivedEncryptionKey {
        let signature = try VaultKeyDeriver.Signature(tryFromString: vault.keygenSignature)
        return try VaultKeyDeriver.lookup(signature: signature)
            .recreateEncryptionKey(password: password, salt: vault.keygenSalt)
    }

    static let password = "correct horse battery staple"
    /// A whole number of milliseconds, which is how the backup stores it.
    static let created = Date(timeIntervalSince1970: 1_790_000_000.25)
    static let userDescription = "Before the trip"

    /// The backup's tags. It and `items` are computed, because the backup's types aren't `Sendable`.
    static var tags: [VaultBackupTag] {
        [
            VaultBackupTag(
                id: UUID(uuidString: "A8582716-0C09-475A-9295-A3C0F0E67251")!,
                title: "Personal",
                color: VaultBackupRGBColor(red: 0.2, green: 0.5, blue: 0.9),
                iconName: "person.fill",
            ),
            VaultBackupTag(
                id: UUID(uuidString: "B349F093-958A-440D-BEA8-E1231E281A5A")!,
                title: "Work",
                color: VaultBackupRGBColor(red: 0, green: 0.47, blue: 0.68),
                iconName: "tag.fill",
            ),
        ]
    }

    static var items: [VaultBackupItem] {
        [
            VaultBackupItem(
                id: UUID(uuidString: "ED314A19-B48C-430A-B280-6540D860542C")!,
                createdDate: Date(timeIntervalSince1970: 1_760_000_000),
                updatedDate: Date(timeIntervalSince1970: 1_770_000_000),
                relativeOrder: 0,
                userDescription: "Personal email",
                tags: [tags[0].id],
                visibility: .always,
                searchableLevel: .full,
                searchPassphraseSalt: nil,
                searchPassphraseDigest: nil,
                killphraseSalt: nil,
                killphraseDigest: nil,
                lockState: .notLocked,
                tintColor: VaultBackupRGBColor(red: 0.9, green: 0.3, blue: 0.1),
                showInQuickType: true,
                previewMode: .titleAndFirstLine,
                item: .otp(data: VaultBackupItem.OTP(
                    secretFormat: "BASE_32",
                    secretData: Data("12345678901234567890".utf8),
                    authType: "totp",
                    period: 30,
                    algorithm: "SHA1",
                    digits: 6,
                    accountName: "alice@example.com",
                    issuer: "Example Mail",
                )),
            ),
            VaultBackupItem(
                id: UUID(uuidString: "C0CF4EE1-08AC-480E-AB5C-DE74624F1D5D")!,
                createdDate: Date(timeIntervalSince1970: 1_760_000_010),
                updatedDate: Date(timeIntervalSince1970: 1_770_000_010),
                relativeOrder: 10,
                userDescription: "",
                tags: [tags[1].id],
                visibility: .always,
                searchableLevel: .onlyTitle,
                searchPassphraseSalt: nil,
                searchPassphraseDigest: nil,
                killphraseSalt: Data(hex: "dfe0a00469c32ac9530ac73c38926134"),
                killphraseDigest: Data(hex: "7834f86149f5ff8242d1ea50ae958e08a82fff95fc0e5f912fa050968a9a5c56"),
                lockState: .notLocked,
                tintColor: nil,
                showInQuickType: false,
                previewMode: .titleOnly,
                item: .otp(data: VaultBackupItem.OTP(
                    secretFormat: "BASE_32",
                    secretData: Data("a bank's hotp secret".utf8),
                    authType: "hotp",
                    counter: 42,
                    algorithm: "SHA256",
                    digits: 8,
                    accountName: "alice",
                    issuer: "Example Bank",
                )),
            ),
            VaultBackupItem(
                id: UUID(uuidString: "4DF9A6D8-E53D-448E-800A-5320F415A9DE")!,
                createdDate: Date(timeIntervalSince1970: 1_760_000_020),
                updatedDate: Date(timeIntervalSince1970: 1_770_000_020),
                relativeOrder: 20,
                userDescription: "",
                tags: [tags[0].id],
                visibility: .onlySearch,
                searchableLevel: .onlyPassphrase,
                searchPassphraseSalt: Data(hex: "3e247a12792f79319a6641e8be118bbc"),
                searchPassphraseDigest: Data(hex: "3009ed6d6e43794ccaa0a63ce0a054f0c6edd54229d76e88731e3aaa1adad5fd"),
                killphraseSalt: nil,
                killphraseDigest: nil,
                lockState: .lockedWithNativeSecurity,
                tintColor: nil,
                showInQuickType: true,
                previewMode: .hidden,
                item: .note(data: VaultBackupItem.Note(
                    title: "Travel plans",
                    rawContents: "# Itinerary\n\n- Fly out on the 3rd\n- Hotel booking **QX-4471**",
                    format: .markdown,
                )),
            ),
            VaultBackupItem(
                id: UUID(uuidString: "9ED6C89F-C860-4FAA-A60E-CE55FA6FB9AD")!,
                createdDate: Date(timeIntervalSince1970: 1_780_000_000),
                updatedDate: Date(timeIntervalSince1970: 1_780_003_600),
                relativeOrder: 30,
                userDescription: "Encrypted note",
                tags: [],
                visibility: .always,
                searchableLevel: .onlyTitle,
                searchPassphraseSalt: nil,
                searchPassphraseDigest: nil,
                killphraseSalt: nil,
                killphraseDigest: nil,
                lockState: .lockedWithNativeSecurity,
                tintColor: nil,
                showInQuickType: true,
                previewMode: .titleAndFirstLine,
                // Carried as it's stored: the backup never decrypts it.
                item: .encrypted(data: VaultBackupItem.Encrypted(
                    version: "1.0.0",
                    title: "Safe combination",
                    data: Data(
                        hex: "2efe7b49ae9bdaf4522496c9e12ae7bb4d67eaa25f50e61ad705ad4dafb75e96"
                            + "3820742f570d1cfab8b2dcd575115ec29ee0a87e8509ddc42ff9b9f3a91ffcf9",
                    ),
                    authentication: Data(hex: "593afcea91fc1dd99fd0c1cb70917d0a"),
                    encryptionIV: Data(hex: "30595c7617c9ef649126b5f2355e1ab6d4040a6077b7eec8915a4681e5191ee2"),
                    keygenSalt: Data(
                        hex: "b50638d63e7e88624fa6e998964b78d58167fdd94d71352822b9cfbd404a3e46"
                            + "0a46c1148ecd0f5300aa492172ada3fb",
                    ),
                    keygenSignature: "vault.keygen.item.fast.v1",
                )),
            ),
        ]
    }
}
