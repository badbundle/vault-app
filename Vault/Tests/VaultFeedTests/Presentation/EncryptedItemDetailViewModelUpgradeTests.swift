import Foundation
import FoundationExtensions
import TestHelpers
import Testing
import VaultKeygen
@testable import VaultFeed

/// Opening an item encrypted with v1 encrypts it again with v2, from the password just entered (VAULT-128). These use
/// the fast derivations debug builds use, with the same shape as the secure ones.
@MainActor
struct EncryptedItemDetailViewModelUpgradeTests {
    @Test
    func startDecryption_v1Item_savesItEncryptedWithV2AndOpensWithTheNewKey() async throws {
        let note = SecureNote(title: "Safe combination", contents: "12-34-56", format: .plain)
        let item = try encrypt(note, with: .Item.Fast.v1, password: "open sesame")
        let metadata = anyVaultItemMetadata()
        let store = VaultStoreEncryptedItemReplacerMock()
        store.replaceEncryptedItemHandler = { _, _, _ in true }
        let sut = makeSUT(item: item, metadata: metadata, itemStore: store)
        sut.enteredEncryptionPassword = "open sesame"

        await sut.startDecryption()

        let (id, old, new) = try #require(store.replaceEncryptedItemArgValues.first)
        #expect(store.replaceEncryptedItemCallCount == 1)
        #expect(id == metadata.id)
        #expect(old == item)
        #expect(new.keygenSignature == VaultKeyDeriver.Signature.itemFastV2.rawValue)
        #expect(new.title == item.title)
        guard case let .decrypted(.secureNote(decrypted), key) = sut.state else {
            Issue.record("Unexpected state \(sut.state)")
            return
        }
        #expect(decrypted == note)
        #expect(key.keyDervier == .itemFastV2)
        #expect(key.salt == new.keygenSalt)
        // The key is the password's, so the item opens with the password, and edits encrypt with v2.
        #expect(try VaultKeyDeriver.Item.Fast.v2.recreateEncryptionKey(password: "open sesame", salt: key.salt) == key)
        let reopened: SecureNote = try VaultItemDecryptor(key: key)
            .decrypt(item: new, expectedItemIdentifier: VaultIdentifiers.Item.secureNote)
        #expect(reopened == note)
    }

    @Test
    func startDecryption_v2Item_isLeftAsItIs() async throws {
        let item = try encrypt(anySecureNote(), with: .Item.Fast.v2, password: "open sesame")
        let store = VaultStoreEncryptedItemReplacerMock()
        let sut = makeSUT(item: item, itemStore: store)
        sut.enteredEncryptionPassword = "open sesame"

        await sut.startDecryption()

        #expect(store.replaceEncryptedItemCallCount == 0)
        #expect(sut.isDecrypted)
    }

    @Test
    func startDecryption_wrongPassword_savesNothing() async throws {
        let item = try encrypt(anySecureNote(), with: .Item.Fast.v1, password: "open sesame")
        let store = VaultStoreEncryptedItemReplacerMock()
        let sut = makeSUT(item: item, itemStore: store)
        sut.enteredEncryptionPassword = "wrong password"

        await sut.startDecryption()

        #expect(store.replaceEncryptedItemCallCount == 0)
        #expect(sut.state.presentationError != nil)
    }

    /// It was edited, or deleted, meanwhile: it opens with the key it's encrypted with now.
    @Test
    func startDecryption_itemNoLongerTheOneOpened_opensWithTheOldKey() async throws {
        let item = try encrypt(anySecureNote(), with: .Item.Fast.v1, password: "open sesame")
        let store = VaultStoreEncryptedItemReplacerMock()
        store.replaceEncryptedItemHandler = { _, _, _ in false }
        let sut = makeSUT(item: item, itemStore: store)
        sut.enteredEncryptionPassword = "open sesame"

        await sut.startDecryption()

        guard case let .decrypted(_, key) = sut.state else {
            Issue.record("Unexpected state \(sut.state)")
            return
        }
        #expect(key.keyDervier == .itemFastV1)
    }

    /// Nothing is said or logged: the item opens as it always did, and moves to v2 another time.
    @Test
    func startDecryption_savingFails_opensWithTheOldKeySilently() async throws {
        let note = anySecureNote()
        let item = try encrypt(note, with: .Item.Fast.v1, password: "open sesame")
        let store = VaultStoreEncryptedItemReplacerMock()
        store.replaceEncryptedItemHandler = { _, _, _ in throw TestError() }
        let sut = makeSUT(item: item, itemStore: store)
        sut.enteredEncryptionPassword = "open sesame"

        await sut.startDecryption()

        guard case let .decrypted(.secureNote(decrypted), key) = sut.state else {
            Issue.record("Unexpected state \(sut.state)")
            return
        }
        #expect(decrypted == note)
        #expect(key.keyDervier == .itemFastV1)
    }

    @Test
    func startDecryption_withoutAStore_opensWithTheOldKey() async throws {
        let item = try encrypt(anySecureNote(), with: .Item.Fast.v1, password: "open sesame")
        let sut = makeSUT(item: item, itemStore: nil)
        sut.enteredEncryptionPassword = "open sesame"

        await sut.startDecryption()

        guard case let .decrypted(_, key) = sut.state else {
            Issue.record("Unexpected state \(sut.state)")
            return
        }
        #expect(key.keyDervier == .itemFastV1)
    }

    /// End to end, through the data model and a store: the item is stored with v2, with nothing else about it
    /// changed, and opens with its password.
    @Test
    func startDecryption_v1RecoveryPhrase_isStoredWithV2AndNothingElseChanged() async throws {
        let phrase = anyRecoveryPhrase(title: "Wallet", passphrase: "extra")
        let item = try encrypt(phrase, with: .Item.Fast.v1, password: "hunter2 hunter2")
        let store = try PersistedLocalVaultStore.inMemory()
        await store.updateCurrentDate { Date(timeIntervalSince1970: 100) }
        var write = uniqueVaultItem(item: .encryptedItem(item), lockState: .lockedWithNativeSecurity).makeWritable()
        write.userDescription = "Wallet"
        try await store.insert(item: write)
        await store.updateCurrentDate { Date(timeIntervalSince1970: 200) }
        let dataModel = anyVaultDataModel(vaultStore: store)
        let changes = SharedMutex(0)
        dataModel.onDataChanged = { changes.modify { $0 += 1 } }
        await dataModel.reloadData()
        let before = try #require(dataModel.items.first)
        let sut = makeSUT(item: item, metadata: before.metadata, itemStore: dataModel)
        sut.enteredEncryptionPassword = "hunter2 hunter2"

        await sut.startDecryption()

        let after = try #require(dataModel.items.first)
        #expect(after.metadata == before.metadata)
        guard case let .encryptedItem(stored) = after.item else {
            Issue.record("Not encrypted: \(after.item)")
            return
        }
        #expect(stored.keygenSignature == VaultKeyDeriver.Signature.itemFastV2.rawValue)
        #expect(changes.value == 1)
        let reopening = makeSUT(item: stored, metadata: after.metadata, itemStore: dataModel)
        reopening.enteredEncryptionPassword = "hunter2 hunter2"
        await reopening.startDecryption()
        guard case let .decrypted(.recoveryPhrase(decrypted), _) = reopening.state else {
            Issue.record("Unexpected state \(reopening.state)")
            return
        }
        #expect(decrypted == phrase)
        #expect(changes.value == 1)
    }
}

// MARK: - Helpers

extension EncryptedItemDetailViewModelUpgradeTests {
    private func makeSUT(
        item: EncryptedItem,
        metadata: VaultItem.Metadata = anyVaultItemMetadata(),
        itemStore: (any VaultStoreEncryptedItemReplacer)?,
    ) -> EncryptedItemDetailViewModel {
        EncryptedItemDetailViewModel(
            item: item,
            metadata: metadata,
            keyDeriverFactory: VaultKeyDeriverFactoryImpl(),
            itemStore: itemStore,
        )
    }

    private func encrypt(
        _ item: some VaultItemEncryptable,
        with keyDeriver: VaultKeyDeriver,
        password: String,
    ) throws -> EncryptedItem {
        try VaultItemEncryptor(key: keyDeriver.createEncryptionKey(password: password)).encrypt(item: item)
    }
}
