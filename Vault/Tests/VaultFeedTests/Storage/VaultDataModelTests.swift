import Foundation
import FoundationExtensions
import TestHelpers
import Testing
import VaultKeygen
@testable import VaultFeed

@MainActor
final class VaultDataModelTests {
    @Test
    func initHasNoStoreSideEffects() {
        let vaultStore = VaultStoreStub()
        let vaultTagStore = VaultTagStoreStub()
        _ = makeSUT(vaultStore: vaultStore, vaultTagStore: vaultTagStore)

        #expect(vaultStore.calledMethods == [])
        #expect(vaultTagStore.calledMethods == [])
    }

    @Test
    func init_initiallyFetchesBackupState() {
        let logger = BackupEventLoggerMock()
        logger.lastBackupEventHandler = { .init(
            backupDate: Date(),
            eventDate: Date(),
            kind: .exportedToPDF,
            payloadHash: .init(value: Data()),
        ) }
        let sut = makeSUT(backupEventLogger: logger)

        #expect(logger.lastBackupEventCallCount == 1)
        #expect(sut.lastBackupEvent != nil)
    }

    @Test
    func init_initiallyFetchesBackupStateNil() {
        let logger = BackupEventLoggerMock()
        logger.lastBackupEventHandler = { nil }
        let sut = makeSUT(backupEventLogger: logger)

        #expect(logger.lastBackupEventCallCount == 1)
        #expect(sut.lastBackupEvent == nil)
    }

    @Test
    func init_monitorsChangesToBackupEventLogger() {
        let logger = BackupEventLoggerMock()
        logger.lastBackupEventHandler = { nil }
        let sut = makeSUT(backupEventLogger: logger)

        #expect(sut.lastBackupEvent == nil)

        let event = VaultBackupEvent(
            backupDate: Date(),
            eventDate: Date(),
            kind: .exportedToPDF,
            payloadHash: .init(value: Data()),
        )
        logger.loggedEventPublisherSubject.send(event)

        #expect(sut.lastBackupEvent == event)

        let event2 = VaultBackupEvent(
            backupDate: Date(),
            eventDate: Date(),
            kind: .exportedToPDF,
            payloadHash: .init(value: .random(count: 32)),
        )
        logger.loggedEventPublisherSubject.send(event2)

        #expect(sut.lastBackupEvent == event2)
    }

    @Test
    func init_initiallyEmptyData() {
        let sut = makeSUT()

        #expect(sut.items == [])
        #expect(sut.itemErrors == [])
        #expect(sut.itemsState == .base)
        #expect(sut.itemsRetrievalError == nil)
        #expect(sut.allTags == [])
        #expect(sut.allTagsState == .base)
        #expect(sut.backupPassword == .notFetched)
        #expect(sut.backupPasswordStatus == .unknown)
        #expect(sut.allTagsRetrievalError == nil)
        #expect(sut.hasAnyItems == false)
    }

    @Test
    func init_initiallyNotQueryingItems() {
        let sut = makeSUT()

        #expect(sut.itemsSearchQuery == "")
        #expect(sut.itemsFilteringByTags == [])
    }

    @Test
    func searchPresentationValues_reflectQueryAndFilters() {
        let sut = makeSUT()
        let originalHash = sut.itemSearchHash

        sut.items = [uniqueVaultItem(), uniqueVaultItem()]
        sut.itemsSearchQuery = "query"
        sut.itemsFilteringByTags = [.new(), .new()]

        #expect(sut.itemSearchHash != originalHash)
        #expect(sut.feedTitle.isEmpty == false)
        #expect(sut.filteringByTagsDescription.isEmpty == false)
        #expect(sut.itemsMatchCountDescription.isEmpty == false)
        #expect(sut.itemsMatchCountDescription != sut.itemsCountDescription)
    }

    @Test
    func feedTitle_usesListTitleWhenNotSearching() {
        let sut = makeSUT()

        #expect(sut.feedTitle.isEmpty == false)
    }

    @Test
    func init_initialPayloadHashIsNil() {
        let store = VaultStoreStub()
        let sut = makeSUT(vaultStore: store)

        #expect(sut.currentPayloadHash == nil)
    }

    @Test
    func setup_computesCurrentPayloadHash() async {
        let store = VaultStoreStub()
        let sut = makeSUT(vaultStore: store)

        await sut.setup()

        #expect(store.calledMethods == [.export])
        #expect(sut.currentPayloadHash != nil)
    }

    @Test
    func loadKillphraseDigester_isNoopWhenAlreadyLoaded() async {
        let keyStore = KillphraseKeyStoreMock()
        keyStore.loadOrCreateHandler = {
            try KeyData<32>(data: Data(repeating: 1, count: 32))
        }
        let sut = makeSUT(killphraseKeyStore: keyStore)

        await sut.loadKillphraseDigester()
        await sut.loadKillphraseDigester()

        #expect(keyStore.loadOrCreateCallCount == 1)
        #expect(sut.killphraseDigester != nil)
    }

    @Test
    func loadKillphraseDigester_swallowsKeyStoreError() async {
        let keyStore = KillphraseKeyStoreMock()
        keyStore.loadOrCreateHandler = { throw TestError() }
        let sut = makeSUT(killphraseKeyStore: keyStore)

        await sut.loadKillphraseDigester()

        #expect(keyStore.loadOrCreateCallCount == 1)
        #expect(sut.killphraseDigester == nil)
    }

    @Test
    func loadSearchPassphraseDigester_isNoopWhenAlreadyLoaded() async {
        let keyStore = SearchPassphraseKeyStoreMock()
        keyStore.loadOrCreateHandler = {
            try KeyData<32>(data: Data(repeating: 2, count: 32))
        }
        let sut = makeSUT(searchPassphraseKeyStore: keyStore)

        await sut.loadSearchPassphraseDigester()
        await sut.loadSearchPassphraseDigester()

        #expect(keyStore.loadOrCreateCallCount == 1)
        #expect(sut.searchPassphraseDigester != nil)
    }

    @Test
    func loadSearchPassphraseDigester_swallowsKeyStoreError() async {
        let keyStore = SearchPassphraseKeyStoreMock()
        keyStore.loadOrCreateHandler = { throw TestError() }
        let sut = makeSUT(searchPassphraseKeyStore: keyStore)

        await sut.loadSearchPassphraseDigester()

        #expect(keyStore.loadOrCreateCallCount == 1)
        #expect(sut.searchPassphraseDigester == nil)
    }

    @Test
    func isSearching_whenQueryingItems() {
        let sut = makeSUT()
        sut.itemsSearchQuery = " \tSOME QUERY 123\n "

        #expect(sut.isSearching == true)
    }

    @Test
    func isSearching_whenNotQueryingItems() {
        let sut = makeSUT()
        sut.itemsSearchQuery = ""
        // filtering tags does not count as searching
        sut.itemsFilteringByTags = [.init(id: UUID())]

        #expect(sut.isSearching == false)
    }

    @Test
    func toggleFiltering_addsTagToFiltering() {
        let sut = makeSUT()
        let tagID = Identifier<VaultItemTag>.new()

        sut.toggleFiltering(tag: tagID)

        #expect(sut.itemsFilteringByTags == [tagID])
    }

    @Test
    func toggleFiltering_removesTagFromFiltering() {
        let sut = makeSUT()
        let tagID = Identifier<VaultItemTag>.new()
        sut.itemsFilteringByTags = [tagID]

        sut.toggleFiltering(tag: tagID)

        #expect(sut.itemsFilteringByTags == [])
    }

    @Test
    func reloadItems_populatesNoItemsFromEmptyStore() async {
        let sut = makeSUT(vaultStore: VaultStoreStub.empty)

        await sut.reloadItems()

        #expect(sut.items == [])
    }

    @Test
    func reloadItems_populatesItemsFromStore() async {
        let store = VaultStoreStub()
        let sut = makeSUT(vaultStore: store)

        await confirmation { confirm in
            store.retrieveHandler = { _ in
                confirm()
                return .init(items: [uniqueVaultItem(), uniqueVaultItem()])
            }

            await sut.reloadData()

            #expect(sut.items.count == 2)
        }
    }

    @Test
    func reloadItems_populatesItemsFromStoreQueryingText() async {
        let store = VaultStoreStub()
        let sut = makeSUT(vaultStore: store)
        sut.itemsSearchQuery = " \tSOME QUERY 123\n "

        await confirmation { confirm in
            store.retrieveHandler = { query in
                #expect(query.filterText == "SOME QUERY 123")
                #expect(query.filterTags == [])
                confirm()
                return .init(items: [uniqueVaultItem(), uniqueVaultItem()])
            }

            await sut.reloadData()

            #expect(sut.items.count == 2)
        }
    }

    @Test
    func reloadItems_loadsItemsQueryingTextAndFiltering() async {
        let store = VaultStoreStub()
        let sut = makeSUT(vaultStore: store)
        sut.itemsSearchQuery = " \tSOME QUERY 123\n "
        let filterTags: Set<Identifier<VaultItemTag>> = [.init(id: UUID())]
        sut.itemsFilteringByTags = filterTags

        await confirmation { confirm in
            store.retrieveHandler = { query in
                #expect(query.filterText == "SOME QUERY 123")
                #expect(query.filterTags == filterTags)
                confirm()
                return .init(items: [uniqueVaultItem(), uniqueVaultItem()])
            }

            await sut.reloadData()

            #expect(sut.items.count == 2)
        }
    }

    @Test
    func reloadItems_presentsErrorOnFailure() async {
        let store = VaultStoreErroring(error: TestError())
        let sut = makeSUT(vaultStore: store)

        await sut.reloadData()

        #expect(sut.itemsRetrievalError != nil)
    }

    @Test
    func reloadItems_clearsExistingError() async {
        let store = VaultStoreStub()
        store.retrieveHandler = { _ in
            throw TestError()
        }
        let sut = makeSUT(vaultStore: store)

        await sut.reloadData()

        store.retrieveHandler = { _ in .empty() }

        await sut.reloadData()

        #expect(sut.itemsRetrievalError == nil)
    }

    @Test
    func reloadItems_loadsHasItems() async {
        let store = VaultStoreStub()
        let sut = makeSUT(vaultStore: store)
        for hasItems in [true, false] {
            store.hasAnyItemsHandler = { hasItems }

            await sut.reloadItems()

            #expect(sut.hasAnyItems == hasItems)
        }
    }

    @Test
    func reloadTags_presentsErrorOnFailure() async {
        let tagStore = VaultTagStoreErroring(error: TestError())
        let sut = makeSUT(vaultTagStore: tagStore)

        await sut.reloadTags()

        #expect(sut.allTagsRetrievalError != nil)
    }

    @Test
    func reloadItems_deletesKillphraseItemsBeforeReturningResults() async {
        let store = VaultStoreStub()
        let killphraseDeleter = VaultStoreKillphraseDeleterMock()
        let keyStore = KillphraseKeyStoreMock()
        keyStore.loadOrCreateHandler = {
            (try? KeyData<32>(data: Data(repeating: 0xAA, count: 32))) ?? .zero()
        }
        let sut = makeSUT(
            vaultStore: store,
            vaultKillphraseDeleter: killphraseDeleter,
            killphraseKeyStore: keyStore,
        )
        // Setup loads the digester. Without it, reloadItems skips the
        // deleter entirely (locked-state behaviour).
        await sut.setup()
        sut.itemsSearchQuery = "hello world"

        await confirmation("Delete called", expectedCount: 1) { confirmDelete in
            killphraseDeleter.deleteItemsHandler = { query, _ in
                #expect(query == "hello world")
                confirmDelete()
                return false
            }

            await confirmation("Retrieve called", expectedCount: 1) { confirmRetrieve in
                store.retrieveHandler = { query in
                    #expect(query.filterText == "hello world")
                    confirmRetrieve()
                    return .empty()
                }

                await sut.reloadItems()
            }
        }
    }

    @Test
    func reloadItems_matchesKillphraseWhenSearchQueryHasTrailingWhitespace() async {
        let store = VaultStoreStub()
        let killphraseDeleter = VaultStoreKillphraseDeleterMock()
        let keyStore = KillphraseKeyStoreMock()
        keyStore.loadOrCreateHandler = {
            (try? KeyData<32>(data: Data(repeating: 0xAA, count: 32))) ?? .zero()
        }
        let sut = makeSUT(
            vaultStore: store,
            vaultKillphraseDeleter: killphraseDeleter,
            killphraseKeyStore: keyStore,
        )
        await sut.setup()
        // Untrimmed query, as delivered by the search bar. The deleter
        // must receive the same sanitized text the search predicate uses,
        // since digests are built from trimmed phrases.
        sut.itemsSearchQuery = " hello world \n"

        await confirmation("Delete called", expectedCount: 1) { confirmDelete in
            killphraseDeleter.deleteItemsHandler = { query, _ in
                #expect(query == "hello world")
                confirmDelete()
                return false
            }

            await sut.reloadItems()
        }
    }

    @Test
    func reloadItems_doesNotInvokeKillphraseDeleterWhenDigesterNeverLoaded() async {
        let killphraseDeleter = VaultStoreKillphraseDeleterMock()
        let sut = makeSUT(vaultKillphraseDeleter: killphraseDeleter)
        // No setup(): the digester is never loaded, matching the
        // vault-still-locked state. The delete pass must be skipped.
        sut.itemsSearchQuery = "hello world"

        await sut.reloadItems()

        #expect(killphraseDeleter.deleteItemsCallCount == 0)
    }

    @Test
    func reloadItems_doesNotInvokeKillphraseDeleterWhenKeyStoreFails() async {
        let killphraseDeleter = VaultStoreKillphraseDeleterMock()
        let keyStore = KillphraseKeyStoreMock()
        keyStore.loadOrCreateHandler = { throw TestError() }
        let sut = makeSUT(
            vaultKillphraseDeleter: killphraseDeleter,
            killphraseKeyStore: keyStore,
        )
        // Setup runs, but the key load fails, so the digester stays nil
        // and killphrase deletion must remain a no-op.
        await sut.setup()
        sut.itemsSearchQuery = "hello world"

        await sut.reloadItems()

        #expect(killphraseDeleter.deleteItemsCallCount == 0)
    }

    @Test
    func reloadItems_syncsAutofillAndNotifiesWhenKillphraseDeletesItems() async {
        let store = VaultStoreStub()
        let killphraseDeleter = VaultStoreKillphraseDeleterMock()
        let vaultOtpAutofillStore = VaultOTPAutofillStoreMock()
        let keyStore = KillphraseKeyStoreMock()
        keyStore.loadOrCreateHandler = {
            (try? KeyData<32>(data: Data(repeating: 0xAA, count: 32))) ?? .zero()
        }
        let sut = makeSUT(
            vaultStore: store,
            vaultKillphraseDeleter: killphraseDeleter,
            vaultOtpAutofillStore: vaultOtpAutofillStore,
            killphraseKeyStore: keyStore,
        )
        await sut.setup()
        sut.itemsSearchQuery = "hello world"
        let remainingItem = uniqueVaultItem()
        var retrievedQueries: [String?] = []

        killphraseDeleter.deleteItemsHandler = { query, _ in
            #expect(query == "hello world")
            return true
        }
        store.retrieveHandler = { query in
            retrievedQueries.append(query.filterText)
            return .init(items: [remainingItem])
        }

        await confirmation("Autofill synced", expectedCount: 1) { confirmSync in
            vaultOtpAutofillStore.syncAllHandler = { items in
                #expect(items.map(\.id) == [remainingItem.id])
                confirmSync()
            }

            await confirmation("Data change notified", expectedCount: 1) { confirmChange in
                sut.onDataChanged = {
                    confirmChange()
                }

                await sut.reloadItems()
            }
        }

        #expect(retrievedQueries == ["hello world", nil])
        #expect(vaultOtpAutofillStore.syncAllCallCount == 1)
    }

    @Test
    func reloadItems_refreshesPayloadHashWhenKillphraseDeletesItems() async throws {
        let store = VaultStoreStub()
        let killphraseDeleter = VaultStoreKillphraseDeleterMock()
        let keyStore = KillphraseKeyStoreMock()
        keyStore.loadOrCreateHandler = {
            (try? KeyData<32>(data: Data(repeating: 0xAA, count: 32))) ?? .zero()
        }
        let sut = makeSUT(
            vaultStore: store,
            vaultKillphraseDeleter: killphraseDeleter,
            killphraseKeyStore: keyStore,
        )
        await sut.setup()
        let hashBeforeDeletion = try #require(sut.currentPayloadHash)
        sut.itemsSearchQuery = "hello world"
        killphraseDeleter.deleteItemsHandler = { _, _ in true }
        // The store's contents change out from under the model when the
        // killphrase fires; auto-backup relies on the refreshed hash to
        // notice, otherwise the deleted items persist in the newest backup.
        store.exportVaultHandler = { userDescription in
            VaultApplicationPayload(
                userDescription: userDescription,
                items: [uniqueVaultItem()],
                tags: [],
            )
        }

        await sut.reloadItems()

        #expect(sut.currentPayloadHash != nil)
        #expect(sut.currentPayloadHash != hashBeforeDeletion)
    }

    @Test
    func reloadItems_doesNotRefreshPayloadHashWhenNoKillphraseDeletionOccurs() async throws {
        let store = VaultStoreStub()
        let sut = makeSUT(vaultStore: store)
        await sut.setup()
        let exportsAfterSetup = store.exportVaultCallCount

        await sut.reloadItems()

        // Plain reloads (every search keystroke) must not trigger a full
        // vault export just to recompute the hash.
        #expect(store.exportVaultCallCount == exportsAfterSetup)
    }

    @Test
    func insert_refreshesPayloadHashAndNotifiesDataChanged() async throws {
        let store = VaultStoreStub()
        let sut = makeSUT(vaultStore: store)
        await sut.setup()
        let hashBeforeInsert = try #require(sut.currentPayloadHash)
        store.exportVaultHandler = { userDescription in
            VaultApplicationPayload(
                userDescription: userDescription,
                items: [uniqueVaultItem()],
                tags: [],
            )
        }

        try await confirmation("Data change notified", expectedCount: 1) { confirmChange in
            sut.onDataChanged = {
                confirmChange()
            }

            try await sut.insert(item: uniqueVaultItem().makeWritable())
        }

        #expect(sut.currentPayloadHash != nil)
        #expect(sut.currentPayloadHash != hashBeforeInsert)
    }

    @Test
    func incrementCounter_refreshesPayloadHash() async throws {
        let store = VaultStoreStub()
        let sut = makeSUT(vaultStore: store)
        await sut.setup()
        let hashBeforeIncrement = try #require(sut.currentPayloadHash)
        store.exportVaultHandler = { userDescription in
            VaultApplicationPayload(
                userDescription: userDescription,
                items: [uniqueVaultItem()],
                tags: [],
            )
        }

        try await sut.incrementCounter(id: .new())

        #expect(sut.currentPayloadHash != nil)
        #expect(sut.currentPayloadHash != hashBeforeIncrement)
    }

    @Test
    func insert_createsItemInStoreAndReloads() async throws {
        let store = VaultStoreStub()
        let sut = makeSUT(vaultStore: store)
        let item = uniqueVaultItem().makeWritable()

        try await sut.insert(item: item)

        #expect(store.calledMethods == [
            .insert,
            .retrieve, // reload items
            .export, // export for payload hash
        ])
    }

    @Test
    func update_updatesItemInvalidatesAndReloads() async throws {
        let store = VaultStoreStub()
        let cache1 = VaultItemCacheMock()
        let cache2 = VaultItemCacheMock()
        let sut = makeSUT(vaultStore: store, itemCaches: [cache1, cache2])
        let item = uniqueVaultItem().makeWritable()

        try await sut.update(itemID: .new(), data: item)

        #expect(store.calledMethods == [
            .update,
            .retrieve, // reload items
            .export, // export for payload hash
            .retrieve, // sync to OTP autofill store
        ])
        #expect(cache1.vaultItemCacheClearCallCount == 1)
        #expect(cache2.vaultItemCacheClearCallCount == 1)
    }

    @Test
    func delete_deletesItemInvalidatesAndReloads() async throws {
        let store = VaultStoreStub()
        let cache1 = VaultItemCacheMock()
        let cache2 = VaultItemCacheMock()
        let sut = makeSUT(vaultStore: store, itemCaches: [cache1, cache2])

        try await sut.delete(itemID: .new())

        #expect(store.calledMethods == [
            .delete,
            .retrieve, // reload items
            .export, // export for payload hash
            .retrieve, // sync to OTP autofill store
        ])
        #expect(cache1.vaultItemCacheClearCallCount == 1)
        #expect(cache2.vaultItemCacheClearCallCount == 1)
    }

    @Test
    func reorder_reordersItemsInStore() async throws {
        let store = VaultStoreStub()
        let sut = makeSUT(vaultStore: store)
        let items = [uniqueVaultItem(), uniqueVaultItem()].map(\.id)

        try await sut.reorder(items: Set(items), to: .start)

        #expect(store.calledMethods == [.reorder, .export])
    }

    @Test
    func insertTag_createsTagInStoreAndReloads() async throws {
        let store = VaultTagStoreStub()
        let sut = makeSUT(vaultTagStore: store)
        let tag = anyVaultItemTag().makeWritable()

        try await sut.insert(tag: tag)

        #expect(store.calledMethods == [.insertTag, .retrieveTags])
    }

    @Test
    func updateTag_updatesTagInStoreAndReloads() async throws {
        let store = VaultTagStoreStub()
        let sut = makeSUT(vaultTagStore: store)
        let tag = anyVaultItemTag().makeWritable()

        try await sut.update(tagID: .new(), data: tag)

        #expect(store.calledMethods == [.updateTag, .retrieveTags])
    }

    @Test
    func deleteTag_deletesTagInStoreAndReloads() async throws {
        let tagStore = VaultTagStoreStub()
        let sut = makeSUT(vaultTagStore: tagStore)

        try await sut.delete(tagID: .new())

        #expect(tagStore.calledMethods == [.deleteTag, .retrieveTags])
    }

    @Test
    func deleteTag_removesFromCurrentFilteringAndReloads() async throws {
        let store = VaultStoreStub()
        let tagStore = VaultTagStoreStub()
        let sut = makeSUT(vaultStore: store, vaultTagStore: tagStore)
        let tagID = Identifier<VaultItemTag>.new()
        sut.itemsFilteringByTags = [tagID]

        try await sut.delete(tagID: tagID)

        #expect(store.calledMethods == [.retrieve, .export])
        #expect(sut.itemsFilteringByTags == [])
    }

    @Test
    func makeExport_exportsFromVaultStore() async throws {
        let store = VaultStoreStub()
        let tagStore = VaultTagStoreStub()
        let sut = makeSUT(vaultStore: store, vaultTagStore: tagStore)

        let payload = VaultApplicationPayload(userDescription: "any", items: [], tags: [])
        store.exportVaultHandler = { _ in payload }
        let exported = try await sut.makeExport(userDescription: "desc")

        #expect(exported == payload)
        #expect(store.calledMethods == [.export])
        #expect(tagStore.calledMethods == [])
    }

    @Test
    func loadBackupPassword_setsFetchedFromStore() async {
        let store = BackupPasswordStoreMock()
        let password = DerivedEncryptionKey(key: .zero(), salt: Data(), keyDervier: .testing)
        store.fetchPasswordHandler = { password }
        let sut = makeSUT(backupPasswordStore: store)

        await sut.loadBackupPassword()

        #expect(sut.backupPassword == .fetched(password))
        #expect(store.fetchPasswordCallCount == 1)
    }

    @Test
    func loadBackupPassword_setsNotCreatedIfNotInStore() async {
        let store = BackupPasswordStoreMock()
        store.fetchPasswordHandler = { nil }
        let sut = makeSUT(backupPasswordStore: store)

        await sut.loadBackupPassword()

        #expect(sut.backupPassword == .notCreated)
        #expect(store.fetchPasswordCallCount == 1)
    }

    @Test
    func loadBackupPassword_setsErrorIfStoreError() async {
        let store = BackupPasswordStoreMock()
        store.fetchPasswordHandler = { throw TestError() }
        let sut = makeSUT(backupPasswordStore: store)

        await sut.loadBackupPassword()

        #expect(sut.backupPassword.isError == true)
        #expect(store.fetchPasswordCallCount == 1)
    }

    @Test
    func loadBackupPassword_updatesStatusToSet() async {
        let store = BackupPasswordStoreMock()
        let metadata = BackupPasswordMetadata(lastSetDate: Date(timeIntervalSince1970: 1_700_000_000))
        store.fetchPasswordHandler = { DerivedEncryptionKey(key: .zero(), salt: Data(), keyDervier: .testing) }
        store.fetchPasswordMetadataHandler = { metadata }
        let sut = makeSUT(backupPasswordStore: store)

        await sut.loadBackupPassword()

        #expect(sut.backupPasswordStatus == .set(metadata))
    }

    @Test
    func loadBackupPassword_statusIsSetEvenIfMetadataUnavailable() async {
        let store = BackupPasswordStoreMock()
        store.fetchPasswordHandler = { DerivedEncryptionKey(key: .zero(), salt: Data(), keyDervier: .testing) }
        store.fetchPasswordMetadataHandler = { throw TestError() }
        let sut = makeSUT(backupPasswordStore: store)

        await sut.loadBackupPassword()

        #expect(sut.backupPasswordStatus == .set(BackupPasswordMetadata(lastSetDate: nil)))
    }

    @Test
    func loadBackupPassword_updatesStatusToNotSetIfNotInStore() async {
        let store = BackupPasswordStoreMock()
        store.fetchPasswordHandler = { nil }
        store.fetchPasswordMetadataHandler = { .init(lastSetDate: nil) }
        let sut = makeSUT(backupPasswordStore: store)
        await sut.loadBackupPasswordStatus()

        await sut.loadBackupPassword()

        #expect(sut.backupPasswordStatus == .notSet)
    }

    @Test
    func loadBackupPassword_errorDoesNotUpdateStatus() async {
        let store = BackupPasswordStoreMock()
        store.fetchPasswordHandler = { throw TestError() }
        store.fetchPasswordMetadataHandler = { .init(lastSetDate: nil) }
        let sut = makeSUT(backupPasswordStore: store)
        await sut.loadBackupPasswordStatus()

        await sut.loadBackupPassword()

        #expect(sut.backupPasswordStatus == .set(.init(lastSetDate: nil)))
    }

    @Test
    func storeBackupPassword_setsInStoreAndUpdatesEntry() async throws {
        let store = BackupPasswordStoreMock()
        store.setHandler = { _ in }
        let sut = makeSUT(backupPasswordStore: store)

        let password = DerivedEncryptionKey(key: .random(), salt: Data(), keyDervier: .testing)
        try await sut.store(backupPassword: password)

        #expect(sut.backupPassword == .fetched(password))
        #expect(store.setCallCount == 1)
    }

    @Test
    func storeBackupPassword_errorDoesNotUpdateEntry() async throws {
        let store = BackupPasswordStoreMock()
        store.setHandler = { _ in throw TestError() }
        let sut = makeSUT(backupPasswordStore: store)

        let password = DerivedEncryptionKey(key: .random(), salt: Data(), keyDervier: .testing)
        await #expect(throws: (any Error).self) {
            try await sut.store(backupPassword: password)
        }

        #expect(sut.backupPassword == .notFetched) // still initial value
        #expect(store.setCallCount == 1)
    }

    @Test
    func storeBackupPassword_updatesStatusFromStore() async throws {
        let store = BackupPasswordStoreMock()
        let metadata = BackupPasswordMetadata(lastSetDate: Date(timeIntervalSince1970: 1_700_000_000))
        store.fetchPasswordMetadataHandler = { metadata }
        let sut = makeSUT(backupPasswordStore: store)

        let password = DerivedEncryptionKey(key: .random(), salt: Data(), keyDervier: .testing)
        try await sut.store(backupPassword: password)

        #expect(sut.backupPasswordStatus == .set(metadata))
    }

    @Test
    func storeBackupPassword_statusIsSetEvenIfMetadataUnavailable() async throws {
        let store = BackupPasswordStoreMock()
        store.fetchPasswordMetadataHandler = { throw TestError() }
        let sut = makeSUT(backupPasswordStore: store)

        let password = DerivedEncryptionKey(key: .random(), salt: Data(), keyDervier: .testing)
        try await sut.store(backupPassword: password)

        #expect(sut.backupPasswordStatus == .set(BackupPasswordMetadata(lastSetDate: nil)))
    }

    @Test
    func storeBackupPassword_errorDoesNotUpdateStatus() async throws {
        let store = BackupPasswordStoreMock()
        store.setHandler = { _ in throw TestError() }
        let sut = makeSUT(backupPasswordStore: store)

        let password = DerivedEncryptionKey(key: .random(), salt: Data(), keyDervier: .testing)
        await #expect(throws: (any Error).self) {
            try await sut.store(backupPassword: password)
        }

        #expect(sut.backupPasswordStatus == .unknown)
    }

    @Test
    func loadBackupPasswordStatus_setIfStoreHasMetadata() async {
        let store = BackupPasswordStoreMock()
        let metadata = BackupPasswordMetadata(lastSetDate: Date(timeIntervalSince1970: 1_700_000_000))
        store.fetchPasswordMetadataHandler = { metadata }
        let sut = makeSUT(backupPasswordStore: store)

        await sut.loadBackupPasswordStatus()

        #expect(sut.backupPasswordStatus == .set(metadata))
        #expect(sut.backupPasswordStatus.isSet)
    }

    @Test
    func loadBackupPasswordStatus_notSetIfStoreHasNoPassword() async {
        let store = BackupPasswordStoreMock()
        store.fetchPasswordMetadataHandler = { nil }
        let sut = makeSUT(backupPasswordStore: store)

        await sut.loadBackupPasswordStatus()

        #expect(sut.backupPasswordStatus == .notSet)
        #expect(!sut.backupPasswordStatus.isSet)
    }

    @Test
    func loadBackupPasswordStatus_unknownIfFirstReadFails() async {
        let store = BackupPasswordStoreMock()
        store.fetchPasswordMetadataHandler = { throw TestError() }
        let sut = makeSUT(backupPasswordStore: store)

        await sut.loadBackupPasswordStatus()

        #expect(sut.backupPasswordStatus == .unknown)
    }

    /// A status the user has seen mustn't disappear because a later read failed.
    @Test
    func loadBackupPasswordStatus_errorKeepsKnownSetStatus() async {
        let store = BackupPasswordStoreMock()
        let metadata = BackupPasswordMetadata(lastSetDate: Date(timeIntervalSince1970: 1_700_000_000))
        store.fetchPasswordMetadataHandler = { metadata }
        let sut = makeSUT(backupPasswordStore: store)
        await sut.loadBackupPasswordStatus()

        store.fetchPasswordMetadataHandler = { throw TestError() }
        await sut.loadBackupPasswordStatus()

        #expect(sut.backupPasswordStatus == .set(metadata))
    }

    @Test
    func loadBackupPasswordStatus_errorAfterStoringKeepsSetStatus() async throws {
        let store = BackupPasswordStoreMock()
        store.fetchPasswordMetadataHandler = { .init(lastSetDate: nil) }
        let sut = makeSUT(backupPasswordStore: store)
        try await sut.store(backupPassword: DerivedEncryptionKey(key: .random(), salt: Data(), keyDervier: .testing))

        store.fetchPasswordMetadataHandler = { throw TestError() }
        await sut.loadBackupPasswordStatus()

        #expect(sut.backupPasswordStatus == .set(.init(lastSetDate: nil)))
    }

    @Test
    func loadBackupPasswordStatus_errorKeepsKnownNotSetStatus() async {
        let store = BackupPasswordStoreMock()
        store.fetchPasswordMetadataHandler = { nil }
        let sut = makeSUT(backupPasswordStore: store)
        await sut.loadBackupPasswordStatus()

        store.fetchPasswordMetadataHandler = { throw TestError() }
        await sut.loadBackupPasswordStatus()

        #expect(sut.backupPasswordStatus == .notSet)
    }

    /// The status is shown on surfaces that aren't behind device authentication, so loading it must
    /// never load the password itself (which would prompt for authentication).
    @Test
    func loadBackupPasswordStatus_doesNotLoadPassword() async {
        let store = BackupPasswordStoreMock()
        store.fetchPasswordMetadataHandler = { .init(lastSetDate: nil) }
        let sut = makeSUT(backupPasswordStore: store)

        await sut.loadBackupPasswordStatus()

        #expect(store.fetchPasswordCallCount == 0)
        #expect(sut.backupPassword == .notFetched)
    }

    @Test
    func purgeSensitiveData_keepsBackupPasswordStatus() async {
        let store = BackupPasswordStoreMock()
        store.fetchPasswordMetadataHandler = { .init(lastSetDate: nil) }
        let sut = makeSUT(backupPasswordStore: store)
        await sut.loadBackupPasswordStatus()

        sut.purgeSensitiveData()

        #expect(sut.backupPasswordStatus == .set(.init(lastSetDate: nil)))
    }

    @Test
    func backupPassword_errorState() async {
        let store = BackupPasswordStoreMock()
        store.fetchPasswordHandler = { throw TestError() }
        let sut = makeSUT(backupPasswordStore: store)

        await sut.loadBackupPassword()

        #expect(sut.backupPassword.isRetryable == true)
    }

    @Test
    func backupPassword_notFetched() {
        let store = BackupPasswordStoreMock()
        let sut = makeSUT(backupPasswordStore: store)

        #expect(sut.backupPassword.isRetryable == true)
    }

    @Test
    func backupPassword_fetched() async {
        let store = BackupPasswordStoreMock()
        let password = DerivedEncryptionKey(key: .zero(), salt: Data(), keyDervier: .testing)
        store.fetchPasswordHandler = { password }
        let sut = makeSUT(backupPasswordStore: store)

        await sut.loadBackupPassword()

        #expect(sut.backupPassword.isRetryable == false)
        #expect(sut.backupPassword.fetchedPassword == password)
    }

    @Test
    func backupPassword_notCreated() async {
        let store = BackupPasswordStoreMock()
        store.fetchPasswordHandler = { nil }
        let sut = makeSUT(backupPasswordStore: store)

        await sut.loadBackupPassword()

        #expect(sut.backupPassword.isRetryable == false)
    }

    @Test
    func purgeSensitiveData_clearsBackupPassword() async {
        let store = BackupPasswordStoreMock()
        store.fetchPasswordHandler = { DerivedEncryptionKey(key: .random(), salt: Data(), keyDervier: .testing) }
        let sut = makeSUT(backupPasswordStore: store)

        await sut.loadBackupPassword()
        sut.purgeSensitiveData()

        #expect(sut.backupPassword == .notFetched)
    }

    @Test
    func deleteVault_removesAllDataFromVault() async throws {
        let deleter = VaultStoreDeleterMock()
        let vaultOtpAutofillStore = VaultOTPAutofillStoreMock()
        let sut = makeSUT(vaultDeleter: deleter, vaultOtpAutofillStore: vaultOtpAutofillStore)

        try await confirmation(expectedCount: 2) { confirm in
            deleter.deleteVaultHandler = {
                confirm()
            }

            vaultOtpAutofillStore.removeAllHandler = {
                confirm()
            }

            try await sut.deleteVault()
        }
    }

    @Test
    func deleteVault_reloadsData() async throws {
        let vaultStore = VaultStoreStub()
        let vaultTagStore = VaultTagStoreStub()
        let sut = makeSUT(vaultStore: vaultStore, vaultTagStore: vaultTagStore)

        try await sut.deleteVault()

        #expect(vaultStore.calledMethods == [.retrieve])
        #expect(vaultTagStore.calledMethods == [.retrieveTags])
    }

    @Test
    func code_returnsMatchingItemFromLoadedItems() {
        let expected = uniqueVaultItem()
        let sut = makeSUT()
        sut.items = [uniqueVaultItem(), expected]

        #expect(sut.code(id: expected.id) == expected)
        #expect(sut.code(id: .new()) == nil)
    }

    @Test
    func incrementCounter_incrementsStoreReloadsAndNotifiesChange() async throws {
        let store = VaultStoreStub()
        let sut = makeSUT(vaultStore: store)

        try await confirmation { confirm in
            sut.onDataChanged = {
                confirm()
            }

            try await sut.incrementCounter(id: .new())
        }

        #expect(store.incrementCounterCallCount == 1)
        #expect(store.calledMethods == [
            .retrieve, // reload items
            .export, // export for payload hash
        ])
    }

    @Test
    func autofillStoreHelpers_forwardToStore() async throws {
        let autofillStore = VaultOTPAutofillStoreMock()
        let sut = makeSUT(vaultOtpAutofillStore: autofillStore)
        let id = UUID()

        let identities = try await sut.getOTPAutofillStoreIdentities()
        try await sut.removeOTPItemFromAutofillStore(id: id)

        #expect(identities == [])
        #expect(autofillStore.getAllIdentitiesCallCount == 1)
        #expect(autofillStore.removeCallCount == 1)
        #expect(autofillStore.removeArgValues.first?.id == id)
    }

    @Test
    func importMerge_mergesDataFromImporter() async throws {
        let importer = VaultStoreImporterMock()
        let sut = makeSUT(vaultImporter: importer)

        try await confirmation { confirm in
            importer.importAndMergeVaultHandler = { _ in
                confirm()
            }

            try await sut.importMerge(payload: anyApplicationPayload())

            #expect(importer.importAndMergeVaultCallCount == 1)
            #expect(importer.importAndOverrideVaultCallCount == 0)
        }
    }

    @Test
    func importMerge_reloadsStores() async throws {
        let vaultStore = VaultStoreStub()
        let vaultTagStore = VaultTagStoreStub()
        let vaultOtpAutofillStore = VaultOTPAutofillStoreMock()
        let sut = makeSUT(
            vaultStore: vaultStore,
            vaultTagStore: vaultTagStore,
            vaultOtpAutofillStore: vaultOtpAutofillStore,
        )

        try await sut.importMerge(payload: anyApplicationPayload())

        #expect(vaultStore.calledMethods == [
            .retrieve, // reload items
            .export, // export for payload hash
            .retrieve, // sync to OTP autofill store
        ])
        #expect(vaultTagStore.calledMethods == [.retrieveTags])
        #expect(vaultOtpAutofillStore.syncAllCallCount == 1)
    }

    @Test
    func importOverride_mergesDataFromImporter() async throws {
        let importer = VaultStoreImporterMock()
        let sut = makeSUT(vaultImporter: importer)

        try await confirmation { confirm in
            importer.importAndOverrideVaultHandler = { _ in
                confirm()
            }

            try await sut.importOverride(payload: anyApplicationPayload())

            #expect(importer.importAndMergeVaultCallCount == 0)
            #expect(importer.importAndOverrideVaultCallCount == 1)
        }
    }

    @Test
    func importOverride_reloadsStores() async throws {
        let vaultStore = VaultStoreStub()
        let vaultTagStore = VaultTagStoreStub()
        let vaultOtpAutofillStore = VaultOTPAutofillStoreMock()
        let sut = makeSUT(
            vaultStore: vaultStore,
            vaultTagStore: vaultTagStore,
            vaultOtpAutofillStore: vaultOtpAutofillStore,
        )

        try await sut.importOverride(payload: anyApplicationPayload())

        #expect(vaultStore.calledMethods == [
            .retrieve, // reload items
            .export, // export for payload hash
            .retrieve, // sync to OTP autofill store
        ])
        #expect(vaultTagStore.calledMethods == [.retrieveTags])
        #expect(vaultOtpAutofillStore.syncAllCallCount == 1)
    }

    @Test
    func clearOTPAutofillStore_removesAllItemsFromStore() async throws {
        let vaultOtpAutofillStore = VaultOTPAutofillStoreMock()
        let sut = makeSUT(vaultOtpAutofillStore: vaultOtpAutofillStore)

        try await confirmation { confirm in
            vaultOtpAutofillStore.removeAllHandler = {
                confirm()
            }

            try await sut.clearOTPAutofillStore()

            #expect(vaultOtpAutofillStore.removeAllCallCount == 1)
        }
    }

    @Test
    func clearOTPAutofillStore_throwsErrorOnFailure() async throws {
        let vaultOtpAutofillStore = VaultOTPAutofillStoreMock()
        vaultOtpAutofillStore.removeAllHandler = { throw TestError() }
        let sut = makeSUT(vaultOtpAutofillStore: vaultOtpAutofillStore)

        await #expect(throws: (any Error).self) {
            try await sut.clearOTPAutofillStore()
        }
    }

    @Test
    func insert_otpItem_syncsToAutofillStore() async throws {
        let store = VaultStoreStub()
        let vaultOtpAutofillStore = VaultOTPAutofillStoreMock()
        let sut = makeSUT(vaultStore: store, vaultOtpAutofillStore: vaultOtpAutofillStore)

        let itemID = Identifier<VaultItem>.new()
        store.insertHandler = { _ in itemID }

        let otpCode = anyOTPAuthCode()
        let item = VaultItem.Write(
            relativeOrder: 0,
            userDescription: "Test",
            color: nil,
            item: .otpCode(otpCode),
            tags: [],
            visibility: .always,
            searchableLevel: .full,
            searchPassphraseUpdate: .clear,
            killphraseUpdate: .clear,
            lockState: .notLocked,
            showInQuickType: true,
            previewMode: .titleAndFirstLine,
        )

        try await confirmation { confirm in
            vaultOtpAutofillStore.syncHandler = { id, payload, _, _, _ in
                #expect(id == itemID.rawValue)
                #expect(payload == .otpCode(otpCode))
                confirm()
            }

            try await sut.insert(item: item)

            #expect(vaultOtpAutofillStore.syncCallCount == 1)
        }
    }

    @Test
    func insert_nonOTPItem_syncsToAutofillStore() async throws {
        let store = VaultStoreStub()
        let vaultOtpAutofillStore = VaultOTPAutofillStoreMock()
        let sut = makeSUT(vaultStore: store, vaultOtpAutofillStore: vaultOtpAutofillStore)

        let itemID = Identifier<VaultItem>.new()
        store.insertHandler = { _ in itemID }

        let secureNote = SecureNote(title: "Note", contents: "Content", format: .plain)
        let item = VaultItem.Write(
            relativeOrder: 0,
            userDescription: "Test",
            color: nil,
            item: .secureNote(secureNote),
            tags: [],
            visibility: .always,
            searchableLevel: .full,
            searchPassphraseUpdate: .clear,
            killphraseUpdate: .clear,
            lockState: .notLocked,
            showInQuickType: true,
            previewMode: .titleAndFirstLine,
        )

        try await confirmation { confirm in
            vaultOtpAutofillStore.syncHandler = { id, payload, _, _, _ in
                #expect(id == itemID.rawValue)
                #expect(payload == .secureNote(secureNote))
                confirm()
            }

            try await sut.insert(item: item)

            #expect(vaultOtpAutofillStore.syncCallCount == 1)
        }
    }

    @Test
    func update_otpItem_syncsToAutofillStore() async throws {
        let store = VaultStoreStub()
        let vaultOtpAutofillStore = VaultOTPAutofillStoreMock()
        let sut = makeSUT(vaultStore: store, vaultOtpAutofillStore: vaultOtpAutofillStore)

        let itemID = Identifier<VaultItem>.new()
        let otpCode = anyOTPAuthCode()
        let item = VaultItem.Write(
            relativeOrder: 0,
            userDescription: "Test",
            color: nil,
            item: .otpCode(otpCode),
            tags: [],
            visibility: .always,
            searchableLevel: .full,
            searchPassphraseUpdate: .clear,
            killphraseUpdate: .clear,
            lockState: .notLocked,
            showInQuickType: true,
            previewMode: .titleAndFirstLine,
        )

        try await confirmation { confirm in
            vaultOtpAutofillStore.syncAllHandler = { _ in
                confirm()
            }

            try await sut.update(itemID: itemID, data: item)

            // Updates use full sync since we don't have access to old values
            #expect(vaultOtpAutofillStore.syncAllCallCount == 1)
        }
    }

    @Test
    func update_nonOTPItem_syncsToAutofillStore() async throws {
        let store = VaultStoreStub()
        let vaultOtpAutofillStore = VaultOTPAutofillStoreMock()
        let sut = makeSUT(vaultStore: store, vaultOtpAutofillStore: vaultOtpAutofillStore)

        let itemID = Identifier<VaultItem>.new()
        let secureNote = SecureNote(title: "Note", contents: "Content", format: .plain)
        let item = VaultItem.Write(
            relativeOrder: 0,
            userDescription: "Test",
            color: nil,
            item: .secureNote(secureNote),
            tags: [],
            visibility: .always,
            searchableLevel: .full,
            searchPassphraseUpdate: .clear,
            killphraseUpdate: .clear,
            lockState: .notLocked,
            showInQuickType: true,
            previewMode: .titleAndFirstLine,
        )

        try await confirmation { confirm in
            vaultOtpAutofillStore.syncAllHandler = { _ in
                confirm()
            }

            try await sut.update(itemID: itemID, data: item)

            // Updates use full sync since we don't have access to old values
            #expect(vaultOtpAutofillStore.syncAllCallCount == 1)
        }
    }

    @Test
    func delete_removesFromAutofillStore() async throws {
        let store = VaultStoreStub()
        let vaultOtpAutofillStore = VaultOTPAutofillStoreMock()
        let sut = makeSUT(vaultStore: store, vaultOtpAutofillStore: vaultOtpAutofillStore)

        let itemID = Identifier<VaultItem>.new()

        try await confirmation { confirm in
            vaultOtpAutofillStore.syncAllHandler = { _ in
                confirm()
            }

            try await sut.delete(itemID: itemID)

            // Deletes use full sync to ensure removal works reliably
            #expect(vaultOtpAutofillStore.syncAllCallCount == 1)
        }
    }

    @Test
    func syncAllToOTPAutofillStore_syncsAllItems() async throws {
        let store = VaultStoreStub()
        let vaultOtpAutofillStore = VaultOTPAutofillStoreMock()
        let sut = makeSUT(vaultStore: store, vaultOtpAutofillStore: vaultOtpAutofillStore)

        let item1 = uniqueVaultItem(item: .otpCode(anyOTPAuthCode()))
        let item2 = uniqueVaultItem(item: .secureNote(.init(title: "Note", contents: "Content", format: .plain)))

        store.retrieveHandler = { _ in
            .init(items: [item1, item2])
        }

        try await confirmation { confirm in
            vaultOtpAutofillStore.syncAllHandler = { items in
                #expect(items.count == 2)
                #expect(items[0].id == item1.id)
                #expect(items[1].id == item2.id)
                confirm()
            }

            try await sut.syncAllToOTPAutofillStore()

            #expect(vaultOtpAutofillStore.syncAllCallCount == 1)
        }
    }

    @Test
    func syncAllToOTPAutofillStore_handlesErrors() async throws {
        let store = VaultStoreStub()
        let vaultOtpAutofillStore = VaultOTPAutofillStoreMock()
        let sut = makeSUT(vaultStore: store, vaultOtpAutofillStore: vaultOtpAutofillStore)

        store.retrieveHandler = { _ in
            .init(items: [uniqueVaultItem()])
        }
        vaultOtpAutofillStore.syncAllHandler = { _ in throw TestError() }

        await #expect(throws: (any Error).self) {
            try await sut.syncAllToOTPAutofillStore()
        }
    }
}

// MARK: - Helpers

extension VaultDataModelTests {
    private func makeSUT(
        vaultStore: any VaultStore = VaultStoreStub(),
        vaultTagStore: any VaultTagStore = VaultTagStoreStub(),
        vaultImporter: any VaultStoreImporter = VaultStoreImporterMock(),
        vaultDeleter: any VaultStoreDeleter = VaultStoreDeleterMock(),
        vaultKillphraseDeleter: any VaultStoreKillphraseDeleter = VaultStoreKillphraseDeleterMock(),
        vaultOtpAutofillStore: any VaultOTPAutofillStore = VaultOTPAutofillStoreMock(),
        backupPasswordStore: any BackupPasswordStore = BackupPasswordStoreMock(),
        killphraseKeyStore: any KillphraseKeyStore<KeyData<32>> = StubKillphraseKeyStore(),
        killphraseRehashService: KillphraseRehashService? = nil,
        searchPassphraseKeyStore: any SearchPassphraseKeyStore<KeyData<32>> = StubSearchPassphraseKeyStore(),
        searchPassphraseRehashService: SearchPassphraseRehashService? = nil,
        backupEventLogger: any BackupEventLogger = BackupEventLoggerMock(),
        itemCaches: [any VaultItemCache] = [],
    ) -> VaultDataModel {
        VaultDataModel(
            vaultStore: vaultStore,
            vaultTagStore: vaultTagStore,
            vaultImporter: vaultImporter,
            vaultDeleter: vaultDeleter,
            vaultKillphraseDeleter: vaultKillphraseDeleter,
            vaultOtpAutofillStore: vaultOtpAutofillStore,
            backupPasswordStore: backupPasswordStore,
            killphraseKeyStore: killphraseKeyStore,
            killphraseRehashService: killphraseRehashService,
            searchPassphraseKeyStore: searchPassphraseKeyStore,
            searchPassphraseRehashService: searchPassphraseRehashService,
            backupEventLogger: backupEventLogger,
            itemCaches: itemCaches,
        )
    }

    private func anyApplicationPayload() -> VaultApplicationPayload {
        VaultApplicationPayload(userDescription: "any", items: [], tags: [])
    }
}
