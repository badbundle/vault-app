import Foundation
import FoundationExtensions
import SwiftData
import TestHelpers
import Testing
import VaultBackup
import VaultCore
import VaultKeygen
@testable import VaultFeed

/// Private keys through every layer that encodes and decodes them: item records, the stores, backup items and whole
/// encrypted backups, which PDF backups, auto-backups and transfers all are (G102).
///
/// At rest a private key is only ever an encrypted item, as a recovery phrase is, so each round trip decrypts what
/// comes out the other side and checks the key is exactly what went in. Every way to write one refuses it unencrypted.
@MainActor
struct PrivateKeyStorageTests {
    private let key: DerivedEncryptionKey

    init() throws {
        key = try VaultKeyDeriver.testing.createEncryptionKey(password: "password")
    }

    // MARK: - Item record encoder and decoder

    @Test(arguments: privateKeyFixtures)
    func persistedItem_encodeDecode_roundTripsEncryptedKey(privateKey: PrivateKey) throws {
        let write = try makeEncryptedWrite(privateKey: privateKey)

        let record = try PersistedVaultItemEncoder().encode(item: write)
        let decoded = try PersistedVaultItemDecoder().decode(record: record)

        #expect(record.encryptedItemDetails != nil)
        #expect(record.noteDetails == nil)
        #expect(record.otpDetails == nil)
        #expect(decoded.metadata.lockState == .lockedWithNativeSecurity)
        #expect(decoded.metadata.userDescription == "")
        try expectExactlyEqual(decrypt(decoded), privateKey)
    }

    @Test
    func persistedItem_encode_refusesPlaintextKey() {
        let write = plaintextKey().makeWritable()

        #expect(throws: VaultItemEncodingError.plaintextPrivateKeyNotPersistable) {
            try PersistedVaultItemEncoder().encode(item: write)
        }
    }

    // MARK: - Stores

    /// Every store refuses a key that isn't encrypted, and stores nothing: SwiftData, on SQLite, the records of an
    /// encrypted vault and the encrypted vault file.
    @Test(arguments: VaultStoreEngine.allCases)
    func store_insertPlaintextKey_throwsAndStoresNothing(engine: VaultStoreEngine) async throws {
        let store = try await engine.makeStore()

        await #expect(throws: VaultItemEncodingError.plaintextPrivateKeyNotPersistable) {
            try await store.insert(item: plaintextKey().makeWritable())
        }

        #expect(try await store.retrieve(query: .init()).items.isEmpty)
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func store_updateWithPlaintextKey_throwsAndKeepsTheEncryptedKey(engine: VaultStoreEngine) async throws {
        let store = try await engine.makeStore()
        let original = anyPrivateKey(title: "Original")
        let id = try await store.insert(item: makeEncryptedWrite(privateKey: original))

        await #expect(throws: VaultItemEncodingError.plaintextPrivateKeyNotPersistable) {
            try await store.update(id: id, item: plaintextKey().makeWritable())
        }

        let retrieved = try await store.retrieve(query: .init())
        #expect(retrieved.items.count == 1)
        try expectExactlyEqual(decrypt(#require(retrieved.items.first)), original)
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func store_insertAndRetrieve_roundTripsEncryptedKey(engine: VaultStoreEngine) async throws {
        let store = try await engine.makeStore()
        let privateKey = anyPrivateKey(title: "Signing key", contents: "The laptop's")

        let id = try await store.insert(item: makeEncryptedWrite(privateKey: privateKey))
        let retrieved = try await store.retrieve(query: .init())

        let item = try #require(retrieved.items.first)
        #expect(item.id == id)
        #expect(item.item.privateKey == nil, "Only ever stored encrypted")
        try expectExactlyEqual(decrypt(item), privateKey)
    }

    /// Search finds a key by its title, never by the key or its description, which are encrypted.
    @Test
    func store_searchMatchesTitleButNeverTheEncryptedContents() async throws {
        let store = try makeSwiftDataStore()
        let privateKey = anyPrivateKey(title: "Savings", key: validWIFKey, contents: "cold storage")
        let id = try await store.insert(item: makeEncryptedWrite(privateKey: privateKey))

        #expect(try await store.retrieve(query: .init(filterText: "Savings")).items.map(\.id) == [id])
        for query in [String(validWIFKey.prefix(8)), "cold storage", "WIF", "private"] {
            let results = try await store.retrieve(query: .init(filterText: query))
            #expect(results.items.isEmpty, "Searching for \(query) found the item")
        }
    }

    /// Hidden until its search passphrase is typed, and deleted by its killphrase, as any item is (G1, G8).
    @Test
    func store_hiddenKeyAndKillphrase_workAsForAnyItem() async throws {
        let store = try makeSwiftDataStore()
        let passphraseDigester = SearchPassphraseDigester(key: .zero())
        var write = try makeEncryptedWrite(privateKey: anyPrivateKey(title: "Hidden key"))
        write.visibility = .onlySearch
        write.searchableLevel = .onlyPassphrase
        write.searchPassphraseUpdate = .set(passphraseDigester.makeDigest(phrase: "open sesame"))
        write.killphraseUpdate = .set(testDigester.makeDigest(phrase: "burn it"))
        let id = try await store.insert(item: write)

        #expect(try await store.retrieve(query: .init()).items.isEmpty)
        #expect(try await store.retrieve(
            query: .init(filterText: "Hidden key"),
            searchPassphraseMatcher: passphraseDigester,
        ).items.isEmpty)
        #expect(try await store.retrieve(
            query: .init(filterText: "open sesame"),
            searchPassphraseMatcher: passphraseDigester,
        ).items.map(\.id) == [id])

        #expect(await store.deleteItems(matchingKillphrase: "burn it", using: testDigester))
        #expect(try await store.retrieve(
            query: .init(filterText: "open sesame"),
            searchPassphraseMatcher: passphraseDigester,
        ).items.isEmpty)
    }

    /// Created through the editor, as the app does: stored encrypted with the password, always locked, and saved
    /// without the whitespace that split it over two lines.
    @Test
    func store_endToEnd_createdKeyCanBeDecryptedWithItsPassword() async throws {
        let store = try makeSwiftDataStore()
        let dataModel = anyVaultDataModel(vaultStore: store, vaultTagStore: store)
        let keyDeriverFactory = VaultKeyDeriverFactoryMock()
        keyDeriverFactory.makeVaultItemKeyDeriverHandler = { .testing }
        let adapter = VaultDataModelEditorAdapter(dataModel: dataModel, keyDeriverFactory: keyDeriverFactory)
        var edits = PrivateKeyDetailEdits.new()
        edits.title = "Paper wallet"
        edits.contents = "  The one in the drawer  "
        edits.key = String(validWIFKey.prefix(20)) + "\n" + String(validWIFKey.dropFirst(20)) + "\n"
        edits.newEncryptionPassword = "my password"

        try await adapter.createPrivateKey(initialEdits: edits)
        let item = try #require(try await store.retrieve(query: .init()).items.first)

        let encrypted = try #require(item.item.encryptedItem, "Private key was not stored encrypted")
        let passwordKey = try VaultKeyDeriver.testing.recreateEncryptionKey(
            password: "my password",
            salt: encrypted.keygenSalt,
        )
        let decrypted: PrivateKey = try VaultItemDecryptor(key: passwordKey).decrypt(
            item: encrypted,
            expectedItemIdentifier: VaultIdentifiers.Item.privateKey,
        )
        #expect(item.metadata.lockState == .lockedWithNativeSecurity)
        #expect(item.metadata.userDescription == "")
        #expect(encrypted.title == "Paper wallet")
        expectExactlyEqual(decrypted, PrivateKey(
            title: "Paper wallet",
            key: validWIFKey,
            contents: "The one in the drawer",
        ))
    }

    @Test
    func editor_withoutAPasswordOrKey_refusesToSave() async throws {
        let store = try makeSwiftDataStore()
        let dataModel = anyVaultDataModel(vaultStore: store, vaultTagStore: store)
        let adapter = VaultDataModelEditorAdapter(dataModel: dataModel, keyDeriverFactory: VaultKeyDeriverFactoryMock())
        var edits = PrivateKeyDetailEdits.new()
        edits.key = validWIFKey

        await #expect(throws: VaultDataModelEditorAdapter.PrivateKeyError.missingEncryptionKey) {
            try await adapter.createPrivateKey(initialEdits: edits)
        }
        #expect(try await store.retrieve(query: .init()).items.isEmpty)
    }

    // MARK: - Backup items

    @Test(arguments: privateKeyFixtures)
    func backupItem_encodeDecode_roundTripsEncryptedKey(privateKey: PrivateKey) throws {
        let item = try makeEncryptedItem(privateKey: privateKey)

        let backupItem = try VaultBackupItemEncoder().encode(storedItem: item)
        let decoded = try VaultBackupItemDecoder().decode(backupItem: backupItem)

        guard case .encrypted = backupItem.item else {
            Issue.record("Private key was not backed up as an encrypted item")
            return
        }
        #expect(backupItem.lockState == .lockedWithNativeSecurity)
        #expect(decoded.id == item.id)
        try expectExactlyEqual(decrypt(decoded), privateKey)
    }

    @Test
    func backupItem_encode_refusesPlaintextKey() {
        #expect(throws: VaultItemEncodingError.plaintextPrivateKeyNotPersistable) {
            try VaultBackupItemEncoder().encode(storedItem: plaintextKey())
        }
    }

    // MARK: - Encrypted backups

    /// A PDF backup, an auto-backup and a transfer are all this, so each carries the key encrypted, and restores it.
    @Test
    func encryptedVault_roundTripsEveryKey() throws {
        let backupPassword = DerivedEncryptionKey(key: .random(), salt: .random(count: 32), keyDervier: .testing)
        let items = try privateKeyFixtures.map(makeEncryptedItem(privateKey:))
        let payload = VaultApplicationPayload(userDescription: "Backup", items: items, tags: [])

        let encryptedVault = try EncryptedVaultEncoder(
            clock: EpochClockMock(currentTime: 100),
            backupPassword: backupPassword,
        ).encryptAndEncode(payload: payload)
        let restored = try EncryptedVaultDecoderImpl().decryptAndDecode(
            key: backupPassword.key,
            encryptedVault: encryptedVault,
        )

        #expect(restored.items.map(\.id) == items.map(\.id))
        for (restoredItem, privateKey) in zip(restored.items, privateKeyFixtures) {
            try expectExactlyEqual(decrypt(restoredItem), privateKey)
        }
    }

    @Test
    func encryptedVault_refusesPlaintextKey() {
        let backupPassword = DerivedEncryptionKey(key: .random(), salt: .random(count: 32), keyDervier: .testing)
        let payload = VaultApplicationPayload(userDescription: "", items: [uniqueVaultItem(), plaintextKey()], tags: [])
        let encoder = EncryptedVaultEncoder(clock: EpochClockMock(currentTime: 100), backupPassword: backupPassword)

        #expect(throws: VaultItemEncodingError.plaintextPrivateKeyNotPersistable) {
            try encoder.encryptAndEncode(payload: payload)
        }
    }

    /// Restoring a backup with a key in it, into a vault, keeps it encrypted and locked, and it opens with its own
    /// password.
    @Test
    func restore_importsTheKeyEncrypted() async throws {
        let store = try makeSwiftDataStore()
        let item = try makeEncryptedItem(privateKey: anyPrivateKey(title: "Restored"))

        try await store.importAndMergeVault(payload: .init(userDescription: "", items: [item], tags: []))

        let restored = try #require(try await store.retrieve(query: .init()).items.first)
        #expect(restored.id == item.id)
        #expect(restored.metadata.lockState == .lockedWithNativeSecurity)
        try expectExactlyEqual(decrypt(restored), anyPrivateKey(title: "Restored"))
    }
}

// MARK: - Helpers

extension PrivateKeyStorageTests {
    private func makeSwiftDataStore() throws -> PersistedLocalVaultStore {
        let container = try ModelContainer(
            for: PersistedVaultItem.self, PersistedVaultTag.self,
            configurations: .init(isStoredInMemoryOnly: true),
        )
        return PersistedLocalVaultStore(modelContainer: container)
    }

    private func plaintextKey() -> VaultItem {
        VaultItem(metadata: anyVaultItemMetadata(), item: .privateKey(anyPrivateKey()))
    }

    /// A write for a private key, as the editor makes it: encrypted, always locked, nothing in the description.
    private func makeEncryptedWrite(privateKey: PrivateKey) throws -> VaultItem.Write {
        try VaultItem.Write(
            relativeOrder: .min,
            userDescription: "",
            color: nil,
            item: .encryptedItem(VaultItemEncryptor(key: key).encrypt(item: privateKey)),
            tags: [],
            visibility: .always,
            searchableLevel: .full,
            searchPassphraseUpdate: .clear,
            killphraseUpdate: .clear,
            lockState: .lockedWithNativeSecurity,
            showInQuickType: false,
            previewMode: .titleOnly,
        )
    }

    private func makeEncryptedItem(privateKey: PrivateKey) throws -> VaultItem {
        try VaultItemEncryptor(key: key).encrypt(item: privateKey)
            .wrapInAnyVaultItem(lockState: .lockedWithNativeSecurity, showInQuickType: false, previewMode: .titleOnly)
    }

    private func decrypt(_ item: VaultItem) throws -> PrivateKey {
        let encrypted = try #require(item.item.encryptedItem, "Private key was not encrypted")
        return try VaultItemDecryptor(key: key).decrypt(
            item: encrypted,
            expectedItemIdentifier: VaultIdentifiers.Item.privateKey,
        )
    }
}
