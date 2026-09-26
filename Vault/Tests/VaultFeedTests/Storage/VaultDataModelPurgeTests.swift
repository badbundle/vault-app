import Foundation
import TestHelpers
import Testing
@testable import VaultFeed

/// `purgeVaultContents()`: what the data model forgets when the app locks.
@MainActor
struct VaultDataModelPurgeTests {
    @Test
    func purgeVaultContents_forgetsItemsTagsAndSearch() async throws {
        let tag = anyVaultItemTag()
        let store = GatedVaultStore(items: [uniqueVaultItem(), uniqueVaultItem()], tags: [tag])
        let sut = makeSUT(store: store)
        await sut.reloadData()
        sut.itemsSearchQuery = "a search passphrase"
        sut.toggleFiltering(tag: tag.id)
        #expect(sut.items.count == 2)
        #expect(sut.allTags == [tag])
        #expect(sut.hasAnyItems)

        await sut.purgeVaultContents()

        #expect(sut.items.isEmpty)
        #expect(sut.itemErrors.isEmpty)
        #expect(!sut.hasAnyItems)
        #expect(sut.itemsState == .base)
        #expect(sut.allTags.isEmpty)
        #expect(sut.allTagsState == .base)
        #expect(sut.itemsSearchQuery.isEmpty)
        #expect(sut.itemsFilteringByTags.isEmpty)
    }

    @Test
    func purgeVaultContents_clearsEveryItemCache() async {
        let cache1 = VaultItemCacheMock()
        let cache2 = VaultItemCacheMock()
        let sut = makeSUT(store: GatedVaultStore(), itemCaches: [cache1, cache2])

        await sut.purgeVaultContents()

        #expect(cache1.vaultItemCacheClearAllCallCount == 1)
        #expect(cache2.vaultItemCacheClearAllCallCount == 1)
    }

    @Test
    func purgeVaultContents_alsoPurgesTheBackupPassword() async {
        let backupPasswordStore = BackupPasswordStoreMock()
        backupPasswordStore.fetchPasswordHandler = { anyBackupPassword() }
        let sut = makeSUT(store: GatedVaultStore(), backupPasswordStore: backupPasswordStore)
        await sut.loadBackupPassword()
        #expect(sut.backupPassword.fetchedPassword != nil)

        await sut.purgeVaultContents()

        #expect(sut.backupPassword == .notFetched)
    }

    @Test
    func reloadData_afterPurging_readsTheVaultAgain() async {
        let item = uniqueVaultItem()
        let tag = anyVaultItemTag()
        let sut = makeSUT(store: GatedVaultStore(items: [item], tags: [tag]))
        await sut.reloadData()
        await sut.purgeVaultContents()

        await sut.reloadData()

        #expect(sut.items == [item])
        #expect(sut.allTags == [tag])
    }

    @Test
    func reloadItems_underwayWhenPurged_putsNothingBack() async {
        // The app locking while the feed reads the vault: what the read returns must not reappear.
        let store = GatedVaultStore(items: [uniqueVaultItem()])
        let sut = makeSUT(store: store)
        await store.hold()
        let reload = Task { await sut.reloadItems() }
        await store.waitUntilHolding()

        await sut.purgeVaultContents()
        await store.release()
        await reload.value

        #expect(sut.items.isEmpty)
        #expect(!sut.hasAnyItems)
        #expect(sut.itemsRetrievalError == nil)
    }

    @Test
    func reloadTags_underwayWhenPurged_putsNothingBack() async {
        let store = GatedVaultStore(tags: [anyVaultItemTag()])
        let sut = makeSUT(store: store)
        await store.hold()
        let reload = Task { await sut.reloadTags() }
        await store.waitUntilHolding()

        await sut.purgeVaultContents()
        await store.release()
        await reload.value

        #expect(sut.allTags.isEmpty)
        #expect(sut.allTagsState == .base)
    }

    @Test
    func reloadItems_throughALockedSession_findsNothing() async {
        let store = GatedVaultStore(items: [uniqueVaultItem()])
        let session = VaultStoreSession(target: .plain(store))
        let sut = makeSUT(store: session)
        await sut.reloadData()
        #expect(sut.items.count == 1)

        await session.lock()
        await sut.purgeVaultContents()
        await sut.reloadData()

        #expect(sut.items.isEmpty)
        #expect(sut.allTags.isEmpty)
        #expect(sut.itemsRetrievalError == nil)
    }
}

// MARK: - Helpers

extension VaultDataModelPurgeTests {
    private func makeSUT(
        store: any CompleteVaultStore,
        backupPasswordStore: any BackupPasswordStore = BackupPasswordStoreMock(),
        itemCaches: [any VaultItemCache] = [],
    ) -> VaultDataModel {
        VaultDataModel(
            vaultStore: store,
            vaultTagStore: store,
            vaultImporter: store,
            vaultDeleter: store,
            vaultKillphraseDeleter: store,
            vaultOtpAutofillStore: VaultOTPAutofillStoreMock(),
            backupPasswordStore: backupPasswordStore,
            killphraseKeyStore: StubKillphraseKeyStore(),
            killphraseRehashService: nil,
            searchPassphraseKeyStore: StubSearchPassphraseKeyStore(),
            searchPassphraseRehashService: nil,
            backupEventLogger: BackupEventLoggerMock(),
            itemCaches: itemCaches,
        )
    }
}
