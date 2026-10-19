import Foundation
import FoundationExtensions
import Testing
import VaultCore
import VaultKeygen
@testable import VaultFeed

/// The encrypted item fixtures: an encrypted note, a recovery phrase and a private key, each as the app stores it. See
/// `Fixtures/README.md`.
struct EncryptedItemFixtureTests {
    @Test(arguments: EncryptedItemFixture.all)
    func storedItem_isTheItemTheFixtureWasMadeFrom(fixture: EncryptedItemFixture) throws {
        let stored = try fixture.storedItem()

        #expect(stored.metadata == fixture.metadata)
        let encrypted = try #require(stored.item.encryptedItem)
        #expect(encrypted.version == "1.0.0")
        #expect(encrypted.title == fixture.title)
        #expect(encrypted.keygenSignature == fixture.keygen.rawValue)
        #expect(encrypted.keygenSalt.count == 48)
        #expect(encrypted.encryptionIV.count == 32)
        #expect(encrypted.authentication.count == 16)
    }

    @Test(arguments: EncryptedItemFixture.all)
    func decrypt_withItsPassword_givesTheItemItWasMadeFrom(fixture: EncryptedItemFixture) throws {
        let encrypted = try #require(fixture.storedItem().item.encryptedItem)

        #expect(try EncryptedItemFixture.decrypt(encrypted, password: fixture.password) == fixture.decrypted)
    }

    /// Opening an item encrypted with v1 encrypts it again with v2, and changes nothing else about it (VAULT-128).
    @Test
    func noteKeygenV2_isTheV1NoteWithOnlyItsEncryptionChanged() throws {
        let v1 = try EncryptedItemFixture.note.storedItem()
        let v2 = try EncryptedItemFixture.noteKeygenV2.storedItem()

        #expect(v2.metadata == v1.metadata)
        let v1Encrypted = try #require(v1.item.encryptedItem)
        let v2Encrypted = try #require(v2.item.encryptedItem)
        #expect(v2Encrypted.title == v1Encrypted.title)
        #expect(v2Encrypted.version == v1Encrypted.version)
        #expect(v2Encrypted.keygenSalt != v1Encrypted.keygenSalt)
        #expect(v2Encrypted.encryptionIV != v1Encrypted.encryptionIV)
    }

    @Test(arguments: EncryptedItemFixture.all)
    func decrypt_withAWrongPassword_fails(fixture: EncryptedItemFixture) throws {
        let encrypted = try #require(fixture.storedItem().item.encryptedItem)

        let error = #expect(throws: VaultItemDecryptor.Error.self) {
            try EncryptedItemFixture.decrypt(encrypted, password: fixture.password.uppercased())
        }
        guard case .decryptionFailed = error else {
            Issue.record("Expected .decryptionFailed, got \(String(describing: error))")
            return
        }
    }
}

// MARK: - Fixtures

/// An encrypted item as the app stores it, in a vault payload (version 1: the JSON an encrypted vault's slot holds
/// before it's compressed) with that one item in it. Its details are the `EncryptedItem`: the item's own password
/// derives its key, which decrypts the item's JSON.
///
/// The key is derived with `vault.keygen.item.fast.v1` or `.v2`, as debug builds of the app derive it, which takes
/// milliseconds. Release builds derive with `vault.keygen.item.secure.v1` or `.v2`, which take seconds:
/// `VaultKeyDeriverParameterPinTests` pins their parameters, and `CryptoEngineTests` the derivations they use.
struct EncryptedItemFixture: Sendable, CustomTestStringConvertible {
    var name: String
    var password: String
    var metadata: VaultItem.Metadata
    /// What the item decrypts to.
    var decrypted: VaultItem.Payload
    /// The derivation its key was made with.
    var keygen: VaultKeyDeriver.Signature = .itemFastV1

    var testDescription: String {
        name
    }

    /// The plaintext copy of the title, stored next to the encrypted item.
    var title: String {
        switch decrypted {
        case let .secureNote(note): note.title
        case let .recoveryPhrase(phrase): phrase.title
        case let .privateKey(key): key.title
        case .otpCode, .encryptedItem: ""
        }
    }

    static let note = EncryptedItemFixture(
        name: "encrypted-note-v1.json",
        password: "open sesame",
        metadata: metadata(
            id: "9ED6C89F-C860-4FAA-A60E-CE55FA6FB9AD",
            relativeOrder: 30,
            userDescription: "Encrypted note",
            lockState: .lockedWithNativeSecurity,
        ),
        decrypted: .secureNote(SecureNote(
            title: "Safe combination",
            contents: "Left 12, right 34, left 56.\n\nThe spare key is under the blue plant pot.",
            format: .markdown,
        )),
    )

    static let recoveryPhrase = EncryptedItemFixture(
        name: "encrypted-recovery-phrase-v1.json",
        password: "hunter2 hunter2",
        metadata: metadata(
            id: "52A439BB-AE35-460F-87A8-5325BB5A4326",
            relativeOrder: 40,
            userDescription: "",
            lockState: .notLocked,
        ),
        // BIP39's first test vector, with its passphrase: not a wallet anyone uses.
        decrypted: .recoveryPhrase(RecoveryPhrase(
            title: "Hardware wallet",
            words: Array(repeating: "abandon", count: 11) + ["about"],
            standard: .bip39,
            passphrase: "TREZOR",
            contents: "Kept in the drawer with the spare cable.",
        )),
    )

    /// `note`, opened with its password by a version of Vault with v2 key derivations, which encrypted it again
    /// with `vault.keygen.item.fast.v2` and kept everything else about it (VAULT-128).
    static let noteKeygenV2 = EncryptedItemFixture(
        name: "encrypted-note-keygen-v2.json",
        password: note.password,
        metadata: note.metadata,
        decrypted: note.decrypted,
        keygen: .itemFastV2,
    )

    /// A private key (VAULT-143): the Bitcoin wiki's WIF example, a public test key that no wallet uses.
    static let privateKey = EncryptedItemFixture(
        name: "encrypted-private-key-v1.json",
        password: "tr0ub4dor & 3",
        metadata: metadata(
            id: "C3F1E5A0-3B7D-4C55-9E2A-6D1B8F0A4E27",
            relativeOrder: 50,
            userDescription: "",
            lockState: .lockedWithNativeSecurity,
        ),
        decrypted: .privateKey(PrivateKey(
            title: "Paper wallet",
            key: "KwdMAjGmerYanjeui5SHS7JkmpZvVipYvB2LJGU1ZxJwYvP98617",
            contents: "Printed in 2017, in the safe.",
        )),
        keygen: .itemFastV2,
    )

    /// The items the slot file and the backup corpus hold.
    static let v1 = [note, recoveryPhrase]

    static let all = v1 + [noteKeygenV2, privateKey]

    /// The item as it's stored, read from the test bundle.
    func storedItem() throws -> VaultItem {
        try Self.storedItem(in: GoldenFixture.data(named: name))
    }

    static func storedItem(in data: Data) throws -> VaultItem {
        let state = try EncryptedVaultPayload.decode(VaultSlotPayload(version: 1, data: data))
        #expect(state.items.count == 1)
        return try PersistedVaultItemDecoder().decode(record: #require(state.items.first))
    }

    /// Decrypts the item as the app does when it's opened: the key is derived from the password with the salt and
    /// the derivation the item names, and the item's identifier says what it is.
    static func decrypt(_ item: EncryptedItem, password: String) throws -> VaultItem.Payload {
        let signature = try VaultKeyDeriver.Signature(tryFromString: item.keygenSignature)
        let key = try VaultKeyDeriver.lookup(signature: signature)
            .recreateEncryptionKey(password: password, salt: item.keygenSalt)
        let decryptor = VaultItemDecryptor(key: key)
        switch try decryptor.decryptItemIdentifier(item: item) {
        case VaultIdentifiers.Item.secureNote:
            let note: SecureNote = try decryptor.decrypt(
                item: item,
                expectedItemIdentifier: VaultIdentifiers.Item.secureNote,
            )
            return .secureNote(note)
        case VaultIdentifiers.Item.recoveryPhrase:
            let phrase: RecoveryPhrase = try decryptor.decrypt(
                item: item,
                expectedItemIdentifier: VaultIdentifiers.Item.recoveryPhrase,
            )
            return .recoveryPhrase(phrase)
        case VaultIdentifiers.Item.privateKey:
            let key: PrivateKey = try decryptor.decrypt(
                item: item,
                expectedItemIdentifier: VaultIdentifiers.Item.privateKey,
            )
            return .privateKey(key)
        case let identifier:
            throw UnknownItem(identifier: identifier)
        }
    }

    struct UnknownItem: Error {
        var identifier: String
    }

    private static func metadata(
        id: String,
        relativeOrder: UInt64,
        userDescription: String,
        lockState: VaultItemLockState,
    ) -> VaultItem.Metadata {
        VaultItem.Metadata(
            id: Identifier(id: UUID(uuidString: id)!),
            created: Date(timeIntervalSince1970: 1_780_000_000),
            updated: Date(timeIntervalSince1970: 1_780_003_600),
            relativeOrder: relativeOrder,
            userDescription: userDescription,
            tags: [],
            visibility: .always,
            searchableLevel: .onlyTitle,
            searchPassphrase: nil,
            killphrase: nil,
            lockState: lockState,
            color: nil,
            showInQuickType: true,
            previewMode: .titleAndFirstLine,
        )
    }
}
