import Foundation
import FoundationExtensions
import SwiftData
import Testing
@testable import VaultFeed

/// Every store that implements the vault store contract.
///
/// `VaultStoreContractTests` and `VaultStoreDifferentialTests` run against each of them.
enum VaultStoreEngine: CaseIterable, Sendable, CustomTestStringConvertible {
    /// `PersistedLocalVaultStore`, the SwiftData store, in memory.
    case swiftData
    /// `PersistedLocalVaultStore` on a SQLite file, as the app stores a vault with no app lock password.
    case swiftDataSQLite
    /// `RecordVaultStore`, which holds an unlocked encrypted vault, in memory only.
    case records
    /// `EncryptedVaultStore`: the record store, saving to its slot of an encrypted vault file on every change. The
    /// file is in memory, to keep the suite fast; `EncryptedVaultStoreTests` cover it on disk.
    case encrypted

    var testDescription: String {
        switch self {
        case .swiftData: "SwiftData"
        case .swiftDataSQLite: "SwiftData on SQLite"
        case .records: "records"
        case .encrypted: "encrypted"
        }
    }

    /// A new, empty store.
    ///
    /// Sorts by created date by default, so tests can rely on items coming back in the order they were inserted.
    func makeStore(sortOrder: VaultStoreSortOrder = .createdDate) async throws -> any ContractTestableVaultStore {
        switch self {
        case .swiftData:
            let container = try ModelContainer(
                for: PersistedVaultItem.self,
                configurations: .init(isStoredInMemoryOnly: true),
            )
            let store = PersistedLocalVaultStore(modelContainer: container)
            await store.updateSortOrder(sortOrder)
            return store
        case .swiftDataSQLite:
            let url = URL.temporaryDirectory
                .appending(path: "VaultStoreEngine-\(UUID().uuidString)")
                .appending(path: "vault.sqlite")
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            let container = try ModelContainer(for: PersistedVaultItem.self, configurations: .init(url: url))
            let store = PersistedLocalVaultStore(modelContainer: container)
            await store.updateSortOrder(sortOrder)
            return store
        case .records:
            return RecordVaultStore(sortOrder: sortOrder)
        case .encrypted:
            return try await EncryptedVaultFixture().openStore(sortOrder: sortOrder)
        }
    }
}

/// A vault store, with the test-only access the contract suite needs.
protocol ContractTestableVaultStore: VaultStore, VaultTagStore, VaultStoreImporter, VaultStoreDeleter,
    VaultStoreKillphraseDeleter
{
    func updateSortOrder(_ order: VaultStoreSortOrder) async
    /// Replaces the clock the store dates its writes with.
    func updateCurrentDate(_ currentDate: @escaping @Sendable () -> Date) async
    /// Every stored item, decoded, in the order they're stored.
    func allVaultItems() async throws -> [VaultItem]
    /// Every stored tag, decoded, in the order they're stored.
    func allVaultTags() async throws -> [VaultItemTag]
    /// Stores an OTP algorithm that doesn't exist on the item, so it no longer decodes.
    func corruptItemAlgorithm(id: Identifier<VaultItem>) async throws
    /// The ids of every stored item, whether or not it decodes.
    func storedItemIDs() async throws -> Set<UUID>
}

// MARK: - SwiftData

extension PersistedLocalVaultStore: ContractTestableVaultStore {
    func updateSortOrder(_ order: VaultStoreSortOrder) {
        sortOrder = order
    }

    func updateCurrentDate(_ currentDate: @escaping @Sendable () -> Date) {
        self.currentDate = currentDate
    }

    func allVaultItems() async throws -> [VaultItem] {
        let descriptor = FetchDescriptor<PersistedVaultItem>(predicate: .true)
        let result = try modelContext.fetch(descriptor)
        let decoder = PersistedVaultItemDecoder()
        return try result.map {
            try decoder.decode(record: $0.makeRecord())
        }
    }

    func allVaultTags() async throws -> [VaultItemTag] {
        let descriptor = FetchDescriptor<PersistedVaultTag>(predicate: .true)
        let result = try modelContext.fetch(descriptor)
        let decoder = PersistedVaultTagDecoder()
        return try result.map {
            try decoder.decode(record: $0.makeRecord())
        }
    }

    func corruptItemAlgorithm(id: Identifier<VaultItem>) async throws {
        let uuid = id.rawValue
        var descriptor = FetchDescriptor<PersistedVaultItem>(predicate: #Predicate { item in
            item.id == uuid
        })
        descriptor.fetchLimit = 1
        let existing = try #require(try? modelContext.fetch(descriptor).first, "Item not found")
        existing.otpDetails?.algorithm = "INVALID"

        modelContext.insert(existing)
        try modelContext.save()
    }

    func storedItemIDs() throws -> Set<UUID> {
        try modelContext.fetch(FetchDescriptor<PersistedVaultItem>()).reducedToSet(\.id)
    }
}

// MARK: - Records

extension RecordVaultStore: ContractTestableVaultStore {
    func updateSortOrder(_ order: VaultStoreSortOrder) {
        sortOrder = order
    }

    func updateCurrentDate(_ currentDate: @escaping @Sendable () -> Date) {
        self.currentDate = currentDate
    }

    func allVaultItems() async throws -> [VaultItem] {
        let decoder = PersistedVaultItemDecoder()
        return try state.items.map { try decoder.decode(record: $0) }
    }

    func allVaultTags() async throws -> [VaultItemTag] {
        let decoder = PersistedVaultTagDecoder()
        return try state.tags.map { try decoder.decode(record: $0) }
    }

    func corruptItemAlgorithm(id: Identifier<VaultItem>) async throws {
        let index = try #require(state.items.firstIndex { $0.id == id.rawValue }, "Item not found")
        state.items[index].otpDetails?.algorithm = "INVALID"
    }

    func storedItemIDs() -> Set<UUID> {
        state.items.reducedToSet(\.id)
    }
}

// MARK: - Encrypted

/// Every way the suite looks inside the store also checks that what's saved in the file is exactly what's in memory.
extension EncryptedVaultStore: ContractTestableVaultStore {
    func updateSortOrder(_ order: VaultStoreSortOrder) async {
        await records.updateSortOrder(order)
    }

    func updateCurrentDate(_ currentDate: @escaping @Sendable () -> Date) async {
        await records.updateCurrentDate(currentDate)
    }

    func allVaultItems() async throws -> [VaultItem] {
        let decoder = PersistedVaultItemDecoder()
        return try await requireSavedState().items.map { try decoder.decode(record: $0) }
    }

    func allVaultTags() async throws -> [VaultItemTag] {
        let decoder = PersistedVaultTagDecoder()
        return try await requireSavedState().tags.map { try decoder.decode(record: $0) }
    }

    func corruptItemAlgorithm(id: Identifier<VaultItem>) async throws {
        let index = try #require(await records.state.items.firstIndex { $0.id == id.rawValue }, "Item not found")
        try await records.change { state in
            state.items[index].otpDetails?.algorithm = "INVALID"
        }
    }

    func storedItemIDs() async throws -> Set<UUID> {
        try await requireSavedState().items.reducedToSet(\.id)
    }

    /// The state in memory, after checking the vault's slot of the file holds exactly the same.
    func requireSavedState(sourceLocation: SourceLocation = #_sourceLocation) async throws -> VaultRecordState {
        let persistence = try #require(await records.persistence as? SlotFilePersistence)
        let contents = try #require(try await persistence.file.open())
        let lastSaved = await persistence.slot
        let slot = try contents.reopen(lastSaved)
        let saved = try EncryptedVaultPayload.decode(slot: slot, in: contents)
        let state = await records.state
        #expect(slot.generation == lastSaved.generation, sourceLocation: sourceLocation)
        #expect(saved == state, "The file doesn't hold what's in memory", sourceLocation: sourceLocation)
        return state
    }
}

// MARK: - Assertions

extension ContractTestableVaultStore {
    func assertStoreContains(
        item: VaultItem,
        sourceLocation: SourceLocation = #_sourceLocation,
    ) async throws {
        let allItems = try await allVaultItems()
        let found = try #require(
            allItems.first(where: { $0.id == item.id }),
            "Item not in store",
            sourceLocation: sourceLocation,
        )
        #expect(found == item, sourceLocation: sourceLocation)
    }

    func assertStoreContains(
        exactlyItems: [VaultItem],
        sourceLocation: SourceLocation = #_sourceLocation,
    ) async throws {
        let allItems = try await allVaultItems()
        let actualItems = allItems.sorted(by: { $0.metadata.updated < $1.metadata.updated })
        let expectedItems = exactlyItems.sorted(by: { $0.metadata.updated < $1.metadata.updated })
        #expect(
            actualItems == expectedItems,
            "Store does not contain exactly the specified items.",
            sourceLocation: sourceLocation,
        )
    }

    func assertStoreContains(
        exactlyTags: [VaultItemTag],
        sourceLocation: SourceLocation = #_sourceLocation,
    ) async throws {
        let allTags = try await allVaultTags()
        let actualTags = allTags.sorted(by: { $0.name < $1.name })
        let expectedTags = exactlyTags.sorted(by: { $0.name < $1.name })
        #expect(
            actualTags == expectedTags,
            "Tags not equal",
            sourceLocation: sourceLocation,
        )
    }

    func assertStoreEmpty(sourceLocation: SourceLocation = #_sourceLocation) async throws {
        let allItems = try await allVaultItems()
        let allTags = try await allVaultTags()
        #expect(allItems == [], "Store is not empty!", sourceLocation: sourceLocation)
        #expect(allTags == [], "Store is not empty!", sourceLocation: sourceLocation)
    }
}
