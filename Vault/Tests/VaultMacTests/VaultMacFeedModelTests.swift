import Foundation
import FoundationExtensions
import TestHelpers
import Testing
import VaultCore
@testable import VaultFeed
@testable import VaultMac

@MainActor
struct VaultMacFeedModelTests {
    @Test
    func sidebarSelection_tag_filtersTheListToItsItems() async throws {
        let (sut, store) = try makeSUT()
        let tag = try await store.insertTag(item: .init(name: "Work", color: .default, iconName: "tag"))
        _ = try await store.insert(item: MacTestItems.code(tags: [tag]).makeWritable())
        _ = try await store.insert(item: MacTestItems.note().makeWritable())

        sut.sidebarSelection = .tag(tag)
        await sut.reloadItems()

        #expect(sut.dataModel.itemsFilteringByTags == [tag])
        #expect(sut.dataModel.items.count == 1)

        sut.sidebarSelection = .items
        await sut.reloadItems()

        #expect(sut.dataModel.itemsFilteringByTags.isEmpty)
        #expect(sut.dataModel.items.count == 2)
    }

    @Test
    func search_findsOnlyWhatMatches() async throws {
        let (sut, store) = try makeSUT()
        _ = try await store.insert(item: MacTestItems.code(issuer: "Example", account: "ada").makeWritable())
        _ = try await store.insert(item: MacTestItems.code(issuer: "Other", account: "grace").makeWritable())

        sut.dataModel.itemsSearchQuery = "Exam"
        await sut.reloadItems()

        #expect(sut.dataModel.items.map(\.item.otpCode?.data.issuer) == ["Example"])
    }

    @Test
    func reloadItems_itemNoLongerListed_closesItsPage() async throws {
        let (sut, store) = try makeSUT()
        let id = try await store.insert(item: MacTestItems.code(issuer: "Example").makeWritable())
        await sut.reloadItems()
        sut.selectedItemID = id
        #expect(sut.selectedItem?.id == id)

        sut.dataModel.itemsSearchQuery = "Nothing matches this"
        await sut.reloadItems()

        #expect(sut.selectedItemID == nil)
        #expect(sut.selectedItem == nil)
    }

    @Test
    func showsItems_onlyForItemsAndTags() throws {
        let (sut, _) = try makeSUT()

        sut.sidebarSelection = .backups
        #expect(!sut.showsItems)
        sut.sidebarSelection = .tag(.new())
        #expect(sut.showsItems)
    }

    @Test
    func load_thenSearchingAKillphrase_deletesItsItemQuietly() async throws {
        let (sut, store) = try makeSUT()
        var item = MacTestItems.code(issuer: "Example")
        item.metadata.killphrase = KillphraseDigester(key: Self.killphraseKey).makeDigest(phrase: "kill me")
        _ = try await store.insert(item: item.makeWritable())
        await sut.load()
        #expect(sut.dataModel.items.count == 1)

        sut.dataModel.itemsSearchQuery = "kill me"
        await sut.reloadItems()
        sut.dataModel.itemsSearchQuery = ""
        await sut.reloadItems()

        #expect(sut.dataModel.items.isEmpty)
    }

    @Test
    func load_thenSearchingASearchPassphrase_showsItsHiddenItemOnly() async throws {
        let (sut, store) = try makeSUT()
        var item = MacTestItems.code(issuer: "Hidden")
        item.metadata.visibility = .onlySearch
        item.metadata.searchableLevel = .onlyPassphrase
        item.metadata.searchPassphrase = SearchPassphraseDigester(key: Self.searchKey).makeDigest(phrase: "find me")
        _ = try await store.insert(item: item.makeWritable())
        await sut.load()
        #expect(sut.dataModel.items.isEmpty)

        sut.dataModel.itemsSearchQuery = "find me"
        await sut.reloadItems()

        #expect(sut.dataModel.items.map(\.item.otpCode?.data.issuer) == ["Hidden"])
    }

    private nonisolated static let killphraseKey = (try? KeyData<32>(data: Data(repeating: 0xA1, count: 32))) ?? .zero()
    private nonisolated static let searchKey = (try? KeyData<32>(data: Data(repeating: 0xA2, count: 32))) ?? .zero()

    private func makeSUT() throws -> (VaultMacFeedModel, VaultStoreSession) {
        let store = try PersistedLocalVaultStore.inMemory()
        let session = VaultStoreSession(target: .plain(store))
        let killphraseKeys = KillphraseKeyStoreMock()
        killphraseKeys.loadOrCreateHandler = { Self.killphraseKey }
        let searchKeys = SearchPassphraseKeyStoreMock()
        searchKeys.loadOrCreateHandler = { Self.searchKey }
        let dataModel = VaultDataModel(
            vaultStore: session,
            vaultTagStore: session,
            vaultImporter: session,
            vaultDeleter: session,
            vaultKillphraseDeleter: session,
            vaultOtpAutofillStore: NoCredentialIdentities(),
            backupPasswordStore: BackupPasswordStoreMock(),
            killphraseKeyStore: killphraseKeys,
            killphraseRehashService: nil,
            searchPassphraseKeyStore: searchKeys,
            searchPassphraseRehashService: nil,
            backupEventLogger: BackupEventLoggerMock(),
        )
        return (VaultMacFeedModel(dataModel: dataModel), session)
    }
}
