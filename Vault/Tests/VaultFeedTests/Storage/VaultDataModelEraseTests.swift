import Foundation
import TestHelpers
import Testing
@testable import VaultFeed

/// `resetAfterErase()`, which `VaultRoot.eraseVault()` calls once `VaultEraser` has erased every vault: the data
/// model forgets them, and carries on with the fresh one.
@MainActor
struct VaultDataModelEraseTests {
    @Test
    func resetAfterErase_forgetsTheErasedVaultsAndCarriesOnWithTheFreshOne() async throws {
        let tag = anyVaultItemTag()
        let store = VaultStoreStub()
        store.retrieveHandler = { _ in .init(items: [uniqueVaultItem(), uniqueVaultItem()]) }
        let tagStore = VaultTagStoreStub()
        tagStore.retrieveTagsHandler = { [tag] }
        let backupPasswordStore = BackupPasswordStoreMock()
        backupPasswordStore.fetchPasswordHandler = {
            DerivedEncryptionKey(key: .random(), salt: Data(), keyDervier: .testing)
        }
        let backupEventLogger = BackupEventLoggerMock()
        backupEventLogger.lastBackupEventHandler = {
            VaultBackupEvent(
                backupDate: Date(),
                eventDate: Date(),
                kind: .exportedToPDF,
                payloadHash: .init(value: Data()),
            )
        }
        let secureStorage = InMemorySecureStorage()
        let sut = VaultDataModel(
            vaultStore: store,
            vaultTagStore: tagStore,
            vaultImporter: VaultStoreImporterMock(),
            vaultDeleter: VaultStoreDeleterMock(),
            vaultKillphraseDeleter: VaultStoreKillphraseDeleterMock(),
            vaultOtpAutofillStore: VaultOTPAutofillStoreMock(),
            backupPasswordStore: backupPasswordStore,
            killphraseKeyStore: KillphraseKeyStoreImpl(secureStorage: secureStorage),
            killphraseRehashService: nil,
            searchPassphraseKeyStore: SearchPassphraseKeyStoreImpl(secureStorage: secureStorage),
            searchPassphraseRehashService: nil,
            backupEventLogger: backupEventLogger,
        )
        await sut.setup()
        await sut.reloadData()
        await sut.loadBackupPassword()
        sut.itemsSearchQuery = "a search passphrase"
        let erasedDigester = try #require(sut.killphraseDigester)
        let erasedDigest = erasedDigester.makeDigest(phrase: "a killphrase")
        #expect(sut.items.count == 2)
        #expect(sut.lastBackupEvent != nil)

        // The erase: every vault, its keys and its backup password gone, and a fresh, empty plain store open.
        store.retrieveHandler = { _ in .empty() }
        store.hasAnyItemsHandler = { false }
        tagStore.retrieveTagsHandler = { [] }
        backupPasswordStore.fetchPasswordHandler = { nil }
        backupEventLogger.lastBackupEventHandler = { nil }
        await secureStorage.remove(key: VaultIdentifiers.SecureStorageKey.killphraseKey.rawValue)
        await secureStorage.remove(key: VaultIdentifiers.SecureStorageKey.searchPassphraseKey.rawValue)

        await sut.resetAfterErase()

        #expect(sut.items.isEmpty)
        #expect(!sut.hasVisibleItems)
        #expect(sut.allTags.isEmpty)
        #expect(sut.itemsSearchQuery.isEmpty)
        #expect(sut.itemsFilteringByTags.isEmpty)
        #expect(sut.backupPassword == .notFetched)
        #expect(sut.lastBackupEvent == nil)
        // The digesters are made again, from new keys: nothing digested with the erased ones matches.
        let killphraseDigester = try #require(sut.killphraseDigester)
        #expect(!killphraseDigester.matches(
            query: "a killphrase",
            salt: erasedDigest.salt,
            digest: erasedDigest.digest,
        ))
        #expect(sut.searchPassphraseDigester != nil)

        // The fresh vault works as any other.
        let item = uniqueVaultItem()
        store.retrieveHandler = { _ in .init(items: [item]) }
        store.hasAnyItemsHandler = { true }
        await sut.reloadData()
        #expect(sut.items == [item])
    }
}
