import Foundation
import FoundationExtensions
import SwiftData
import TestHelpers
import Testing
import VaultBackup
import VaultCore
import VaultKeygen
@testable import VaultFeed

/// Recovery phrases through every layer that encodes and decodes them: SwiftData, the store, backup items and whole
/// encrypted backups.
///
/// At rest a recovery phrase is only ever an encrypted item, so each round trip decrypts what comes out the other
/// side and checks the words (and everything else in the phrase) are exactly what went in.
@MainActor
struct RecoveryPhraseStorageTests {
    private let key: DerivedEncryptionKey

    init() throws {
        key = try VaultKeyDeriver.testing.createEncryptionKey(password: "password")
    }

    // MARK: - SwiftData encoder and decoder

    @Test(arguments: recoveryPhraseFixtures)
    func persistedItem_encodeDecode_roundTripsEncryptedPhrase(phrase: RecoveryPhrase) throws {
        let context = try makeModelContext()
        let write = try makeEncryptedWrite(phrase: phrase)

        let persisted = try PersistedVaultItemEncoder(context: context).encode(item: write)
        context.insert(persisted)
        let decoded = try PersistedVaultItemDecoder().decode(item: persisted)

        #expect(persisted.encryptedItemDetails != nil)
        #expect(persisted.noteDetails == nil)
        #expect(persisted.otpDetails == nil)
        #expect(decoded.metadata.lockState == .lockedWithNativeSecurity)
        #expect(decoded.metadata.userDescription == "")
        #expect(decoded.metadata.previewMode == .titleOnly)
        try expectExactlyEqual(decrypt(decoded), phrase)
    }

    @Test
    func persistedItem_encode_refusesPlaintextPhrase() throws {
        let context = try makeModelContext()
        let write = VaultItem(metadata: anyVaultItemMetadata(), item: .recoveryPhrase(anyRecoveryPhrase()))
            .makeWritable()

        #expect(throws: VaultItemEncodingError.plaintextRecoveryPhraseNotPersistable) {
            try PersistedVaultItemEncoder(context: context).encode(item: write)
        }
        #expect(context.insertedModelsArray.isEmpty)
    }

    // MARK: - Store

    @Test(arguments: recoveryPhraseFixtures)
    func store_insertAndRetrieve_roundTripsEncryptedPhrase(phrase: RecoveryPhrase) async throws {
        let store = try makeStore()

        let id = try await store.insert(item: makeEncryptedWrite(phrase: phrase))
        let retrieved = try await store.retrieve(query: .init())

        let item = try #require(retrieved.items.first)
        #expect(retrieved.items.count == 1)
        #expect(retrieved.errors.isEmpty)
        #expect(item.id == id)
        #expect(item.item.recoveryPhrase == nil, "Only ever stored encrypted")
        try expectExactlyEqual(decrypt(item), phrase)
    }

    @Test
    func store_update_reencryptedPhraseReplacesPrevious() async throws {
        let store = try makeStore()
        let id = try await store.insert(item: makeEncryptedWrite(phrase: anyRecoveryPhrase(title: "Before")))
        let updated = anyRecoveryPhrase(
            title: "After",
            words: ["zoo", "zoo", "zoo", "zoo", "zoo", "zoo", "zoo", "zoo", "zoo", "zoo", "zoo", "wrong"],
            passphrase: "new passphrase",
            contents: "new contents",
        )

        try await store.update(id: id, item: makeEncryptedWrite(phrase: updated))
        let retrieved = try await store.retrieve(query: .init())

        #expect(retrieved.items.count == 1)
        try expectExactlyEqual(decrypt(#require(retrieved.items.first)), updated)
    }

    @Test
    func store_insertPlaintextPhraseThrowsAndStoresNothing() async throws {
        let store = try makeStore()
        let write = VaultItem(metadata: anyVaultItemMetadata(), item: .recoveryPhrase(anyRecoveryPhrase()))
            .makeWritable()

        await #expect(throws: VaultItemEncodingError.plaintextRecoveryPhraseNotPersistable) {
            try await store.insert(item: write)
        }

        #expect(try await store.retrieve(query: .init()).items.isEmpty)
    }

    @Test
    func store_updateWithPlaintextPhraseThrowsAndKeepsEncryptedPhrase() async throws {
        let store = try makeStore()
        let original = anyRecoveryPhrase(title: "Original")
        let id = try await store.insert(item: makeEncryptedWrite(phrase: original))
        let plaintext = VaultItem(metadata: anyVaultItemMetadata(), item: .recoveryPhrase(anyRecoveryPhrase()))
            .makeWritable()

        await #expect(throws: VaultItemEncodingError.plaintextRecoveryPhraseNotPersistable) {
            try await store.update(id: id, item: plaintext)
        }

        let retrieved = try await store.retrieve(query: .init())
        #expect(retrieved.items.count == 1)
        try expectExactlyEqual(decrypt(#require(retrieved.items.first)), original)
    }

    @Test
    func store_searchMatchesTitleButNeverTheEncryptedContents() async throws {
        let store = try makeStore()
        let phrase = anyRecoveryPhrase(
            title: "Savings",
            words: Array(repeating: "abandon", count: 11) + ["about"],
            passphrase: "secretpassphrase",
            contents: "cold storage",
        )
        let id = try await store.insert(item: makeEncryptedWrite(phrase: phrase))

        #expect(try await store.retrieve(query: .init(filterText: "Savings")).items.map(\.id) == [id])
        for query in ["abandon", "about", "secretpassphrase", "cold storage", "BIP39", "recovery"] {
            let results = try await store.retrieve(query: .init(filterText: query))
            #expect(results.items.isEmpty, "Searching for \(query) found the item")
        }
    }

    @Test
    func store_endToEnd_createdPhraseCanBeDecryptedWithItsPassword() async throws {
        let store = try makeStore()
        let dataModel = anyVaultDataModel(vaultStore: store, vaultTagStore: store)
        let keyDeriverFactory = VaultKeyDeriverFactoryMock()
        keyDeriverFactory.makeVaultItemKeyDeriverHandler = { .testing }
        let adapter = VaultDataModelEditorAdapter(dataModel: dataModel, keyDeriverFactory: keyDeriverFactory)
        var edits = RecoveryPhraseDetailEdits.new()
        edits.title = "Hardware wallet"
        edits.contents = "  The one in the drawer  "
        edits.applyInput(Array(repeating: "abandon", count: 23).joined(separator: " ") + " art", at: 0)
        edits.seedPassphrase = " exact "
        edits.newEncryptionPassword = "my password"

        try await adapter.createRecoveryPhrase(initialEdits: edits)
        let item = try #require(try await store.retrieve(query: .init()).items.first)

        guard case let .encryptedItem(encrypted) = item.item else {
            Issue.record("Recovery phrase was not stored encrypted")
            return
        }
        let passwordKey = try VaultKeyDeriver.testing.recreateEncryptionKey(
            password: "my password",
            salt: encrypted.keygenSalt,
        )
        let decrypted: RecoveryPhrase = try VaultItemDecryptor(key: passwordKey).decrypt(
            item: encrypted,
            expectedItemIdentifier: VaultIdentifiers.Item.recoveryPhrase,
        )
        #expect(item.metadata.lockState == .lockedWithNativeSecurity)
        #expect(encrypted.title == "Hardware wallet")
        expectExactlyEqual(decrypted, RecoveryPhrase(
            title: "Hardware wallet",
            words: Array(repeating: "abandon", count: 23) + ["art"],
            standard: .bip39,
            passphrase: " exact ",
            contents: "The one in the drawer",
        ))
    }

    // MARK: - Title

    /// The title is stored twice: in plaintext, for the feed and search, and encrypted with the phrase. Renaming in
    /// the editor must update both.
    @Test
    func title_renamingKeepsPlaintextAndEncryptedTitleInSync() async throws {
        let store = try makeStore()
        let dataModel = anyVaultDataModel(vaultStore: store, vaultTagStore: store)
        let id = try await store.insert(item: makeEncryptedWrite(phrase: anyRecoveryPhrase(title: "Before")))
        let stored = try #require(try await store.retrieve(query: .init()).items.first)
        let viewModel = try makeViewModel(item: stored, phrase: decrypt(stored), dataModel: dataModel)

        viewModel.startEditing()
        viewModel.editingModel.detail.title = "After"
        await viewModel.saveChanges()

        let renamed = try #require(try await store.retrieve(query: .init()).items.first)
        #expect(renamed.id == id)
        #expect(renamed.item.encryptedItem?.title == "After")
        #expect(try decrypt(renamed).title == "After")
        #expect(viewModel.visibleTitle == "After")
        #expect(try await store.retrieve(query: .init(filterText: "Before")).items.isEmpty)
        #expect(try await store.retrieve(query: .init(filterText: "After")).items.map(\.id) == [id])
    }

    /// Only the encryptor sets the plaintext title, so the two can't differ. If they did (say the stored plaintext
    /// were edited outside Vault), the decrypted title is the one shown, as it's authenticated, and the next save
    /// puts them back in sync.
    @Test
    func title_mismatchedPlaintextIsReplacedByEncryptedTitleOnSave() async throws {
        let store = try makeStore()
        let dataModel = anyVaultDataModel(vaultStore: store, vaultTagStore: store)
        let encrypted = try VaultItemEncryptor(key: key).encrypt(item: anyRecoveryPhrase(title: "Real title"))
        var write = try makeEncryptedWrite(phrase: anyRecoveryPhrase())
        write.item = .encryptedItem(EncryptedItem(
            version: encrypted.version,
            title: "Edited outside Vault",
            data: encrypted.data,
            authentication: encrypted.authentication,
            encryptionIV: encrypted.encryptionIV,
            keygenSalt: encrypted.keygenSalt,
            keygenSignature: encrypted.keygenSignature,
        ))
        try await store.insert(item: write)
        let stored = try #require(try await store.retrieve(query: .init()).items.first)
        let storedEncrypted = try #require(stored.item.encryptedItem)

        let keyDeriverFactory = VaultKeyDeriverFactoryMock()
        keyDeriverFactory.lookupVaultKeyDeriverHandler = { _ in .testing }
        let decryption = EncryptedItemDetailViewModel(
            item: storedEncrypted,
            metadata: stored.metadata,
            keyDeriverFactory: keyDeriverFactory,
        )
        decryption.enteredEncryptionPassword = "password"
        await decryption.startDecryption()
        guard case let .decrypted(.recoveryPhrase(phrase), decryptedKey) = decryption.state else {
            Issue.record("Expected a decrypted recovery phrase, got \(decryption.state)")
            return
        }
        let viewModel = makeViewModel(item: stored, phrase: phrase, key: decryptedKey, dataModel: dataModel)
        #expect(viewModel.visibleTitle == "Real title")

        viewModel.startEditing()
        viewModel.editingModel.detail.contents = "Any change"
        await viewModel.saveChanges()

        let resynced = try #require(try await store.retrieve(query: .init()).items.first)
        #expect(resynced.item.encryptedItem?.title == "Real title")
        #expect(try decrypt(resynced).title == "Real title")
    }

    // MARK: - Backup items

    @Test(arguments: recoveryPhraseFixtures)
    func backupItem_encodeDecode_roundTripsEncryptedPhrase(phrase: RecoveryPhrase) throws {
        let item = try makeEncryptedItem(phrase: phrase)

        let backupItem = try VaultBackupItemEncoder().encode(storedItem: item)
        let decoded = try VaultBackupItemDecoder().decode(backupItem: backupItem)

        guard case .encrypted = backupItem.item else {
            Issue.record("Recovery phrase was not backed up as an encrypted item")
            return
        }
        #expect(backupItem.lockState == .lockedWithNativeSecurity)
        #expect(decoded.id == item.id)
        #expect(decoded.metadata.lockState == .lockedWithNativeSecurity)
        try expectExactlyEqual(decrypt(decoded), phrase)
    }

    @Test
    func backupItem_encode_refusesPlaintextPhrase() {
        let item = VaultItem(metadata: anyVaultItemMetadata(), item: .recoveryPhrase(anyRecoveryPhrase()))

        #expect(throws: VaultItemEncodingError.plaintextRecoveryPhraseNotPersistable) {
            try VaultBackupItemEncoder().encode(storedItem: item)
        }
    }

    // MARK: - Encrypted backups

    @Test
    func encryptedVault_roundTripsEveryPhrase() throws {
        let backupPassword = DerivedEncryptionKey(key: .random(), salt: .random(count: 32), keyDervier: .testing)
        let items = try recoveryPhraseFixtures.map(makeEncryptedItem(phrase:))
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
        for (restoredItem, phrase) in zip(restored.items, recoveryPhraseFixtures) {
            try expectExactlyEqual(decrypt(restoredItem), phrase)
        }
    }

    @Test
    func encryptedVault_refusesPlaintextPhrase() {
        let backupPassword = DerivedEncryptionKey(key: .random(), salt: .random(count: 32), keyDervier: .testing)
        let plaintext = VaultItem(metadata: anyVaultItemMetadata(), item: .recoveryPhrase(anyRecoveryPhrase()))
        let payload = VaultApplicationPayload(userDescription: "", items: [uniqueVaultItem(), plaintext], tags: [])
        let encoder = EncryptedVaultEncoder(clock: EpochClockMock(currentTime: 100), backupPassword: backupPassword)

        #expect(throws: VaultItemEncodingError.plaintextRecoveryPhraseNotPersistable) {
            try encoder.encryptAndEncode(payload: payload)
        }
    }
}

// MARK: - Helpers

extension RecoveryPhraseStorageTests {
    private func makeModelContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: PersistedVaultItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true),
        )
        return ModelContext(container)
    }

    private func makeStore() throws -> PersistedLocalVaultStore {
        let container = try ModelContainer(
            for: PersistedVaultItem.self, PersistedVaultTag.self,
            configurations: .init(isStoredInMemoryOnly: true),
        )
        return PersistedLocalVaultStore(modelContainer: container)
    }

    /// A write for a recovery phrase, as the editor makes it: encrypted, always locked, nothing in the description.
    private func makeEncryptedWrite(phrase: RecoveryPhrase) throws -> VaultItem.Write {
        try VaultItem.Write(
            relativeOrder: .min,
            userDescription: "",
            color: nil,
            item: .encryptedItem(VaultItemEncryptor(key: key).encrypt(item: phrase)),
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

    private func makeEncryptedItem(phrase: RecoveryPhrase) throws -> VaultItem {
        try VaultItemEncryptor(key: key).encrypt(item: phrase)
            .wrapInAnyVaultItem(lockState: .lockedWithNativeSecurity, showInQuickType: false, previewMode: .titleOnly)
    }

    /// A detail view model for a decrypted phrase, saving through the real editor, as the app does.
    private func makeViewModel(
        item: VaultItem,
        phrase: RecoveryPhrase,
        key: DerivedEncryptionKey? = nil,
        dataModel: VaultDataModel,
    ) -> RecoveryPhraseDetailViewModel {
        let keyDeriverFactory = VaultKeyDeriverFactoryMock()
        keyDeriverFactory.makeVaultItemKeyDeriverHandler = { .testing }
        return RecoveryPhraseDetailViewModel(
            mode: .editing(phrase: phrase, metadata: item.metadata, existingKey: key ?? self.key),
            dataModel: dataModel,
            editor: VaultDataModelEditorAdapter(dataModel: dataModel, keyDeriverFactory: keyDeriverFactory),
        )
    }

    private func decrypt(_ item: VaultItem) throws -> RecoveryPhrase {
        let encrypted = try #require(item.item.encryptedItem, "Recovery phrase was not encrypted")
        return try VaultItemDecryptor(key: key).decrypt(
            item: encrypted,
            expectedItemIdentifier: VaultIdentifiers.Item.recoveryPhrase,
        )
    }
}
