import Foundation
import FoundationExtensions
import SwiftData

// swiftformat:disable preferCountWhere

/// Uses SwiftData with a CoreData backing layer to persist content.
///
/// Conforms to SwiftData's `ModelActor` to ensure all database operations are thread-safe.
@ModelActor
public final actor PersistedLocalVaultStore {
    public enum Error: Swift.Error {
        case modelNotFound
        case relativeItemNotFound
        case invalidItem
    }

    /// The sort order used by this store.
    ///
    /// This must be consistent for the lifetime of the store and application.
    /// It is how items in the store are fetched and what reorders are performed against.
    /// A change in this will affect the user-percieved order of their items.
    var sortOrder: VaultStoreSortOrder = .relativeOrder

    /// The current time, for the created and updated dates of writes. Tests set it to make dates predictable.
    var currentDate: @Sendable () -> Date = { Date() }
}

// MARK: - VaultStoreReader

extension PersistedLocalVaultStore: VaultStoreReader {
    public var hasAnyItems: Bool {
        get async throws {
            try fetchHasModelsInStorage(model: PersistedVaultItem.self)
        }
    }

    public func retrieve(
        query: VaultStoreQuery,
        searchPassphraseMatcher: (any SearchPassphraseMatcher)?,
    ) async throws -> VaultRetrievalResult<VaultItem> {
        let basePredicate = makePredicate(query: query)
        var passphraseMatchIDs: [UUID] = []
        if let filterText = query.filterText, filterText.isNotEmpty, let matcher = searchPassphraseMatcher {
            passphraseMatchIDs = try fetchSearchPassphraseMatchIDs(query: filterText, matcher: matcher)
        }
        let combinedPredicate: Predicate<PersistedVaultItem>
        if passphraseMatchIDs.isEmpty {
            combinedPredicate = basePredicate
        } else {
            combinedPredicate = #Predicate<PersistedVaultItem> { item in
                basePredicate.evaluate(item) || passphraseMatchIDs.contains(item.id)
            }
        }
        let descriptor = FetchDescriptor<PersistedVaultItem>(
            predicate: combinedPredicate,
            sortBy: sortOrder.vaultItemSortDescriptors,
        )
        let results = try modelContext.fetch(descriptor)
        return .collectFrom(records: results.map { $0.makeRecord() })
    }

    /// Fetches all `onlyPassphrase`-visible items with a stored digest and
    /// returns the IDs of those whose digest verifies against `query` under
    /// the supplied matcher. Iterates every candidate without early exit so
    /// timing does not leak which item matched.
    private func fetchSearchPassphraseMatchIDs(
        query: String,
        matcher: any SearchPassphraseMatcher,
    ) throws -> [UUID] {
        let onlyPassphrase = VaultEncodingConstants.SearchableLevel.onlyPassphrase
        let predicate: Predicate<PersistedVaultItem> = #Predicate { item in
            item.searchableLevel == onlyPassphrase &&
                item.searchPassphraseSalt != nil &&
                item.searchPassphraseDigest != nil
        }
        let descriptor = FetchDescriptor<PersistedVaultItem>(predicate: predicate)
        let candidates = try modelContext.fetch(descriptor)
        var ids: [UUID] = []
        for item in candidates {
            guard let salt = item.searchPassphraseSalt, let digest = item.searchPassphraseDigest else { continue }
            if matcher.matches(query: query, salt: salt, digest: digest) {
                ids.append(item.id)
            }
        }
        return ids
    }

    /// Creates a predicate that returns items when querying.
    private func makePredicate(query: VaultStoreQuery) -> Predicate<PersistedVaultItem> {
        let tagsPredicate = makeTagsPredicate(matchingTags: query.filterTags)
        if let filterText = query.filterText, filterText.isNotEmpty {
            // (1) Searching by text and (2) filtering by tags.
            // We don't need to filter by visibility level since all items should appear.

            let searchPredicate = makeSearchTextPredicate(matchingText: filterText)
            return #Predicate<PersistedVaultItem> {
                searchPredicate.evaluate($0) && tagsPredicate.evaluate($0)
            }
        } else {
            // Only filtering by tags.
            // We need to explicitly filter by items that are "always visible", since the user is not searching.

            let always = VaultEncodingConstants.Visibility.always
            let visibilityPredicate = #Predicate<PersistedVaultItem> {
                $0.visibility == always
            }
            return #Predicate<PersistedVaultItem> {
                visibilityPredicate.evaluate($0) &&
                    tagsPredicate.evaluate($0)
            }
        }
    }

    private func makeTagsPredicate(matchingTags tags: Set<Identifier<VaultItemTag>>) -> Predicate<PersistedVaultItem> {
        if tags.isEmpty {
            // We're not filtering by any tags, so don't check tags.
            return .true
        } else {
            let searchingTagIds = tags.map(\.id).reducedToSet()
            // Performs an "AND" query by checking if all searched tags are present in the item's tags.
            // Since count(where:) is not supported, we use filter().count instead.
            // An item matches if the count of its tags that match our search equals the search count.
            let searchingTagsArray = Array(searchingTagIds)
            let expectedCount = searchingTagsArray.count
            return #Predicate<PersistedVaultItem> { item in
                item.tags.filter { tag in
                    searchingTagsArray.contains(tag.id)
                }.count == expectedCount
            }
        }
    }

    private func makeSearchTextPredicate(matchingText query: String) -> Predicate<PersistedVaultItem> {
        // Compounding queries in SwiftData is a bit rough at the moment.
        // Each Predicate can only contain a single expression, so we must create them seperately
        // then compound them (a big chain of disjunctions leads to "expression too complex" errors).
        //
        // ** SLOW COMPILE TIMES? **
        // Use a MAX of 2 expressions per predicate, or it could lead to EXPONENTIAL compile time increases.
        //
        // ** CRASHES AT RUNTIME DUE TO SQLITE ERRORS? **
        //  - Optional chaining does not seem to work, use `flatMap`.
        //  - Only compare LOCAL CONSTANTS, create local variables outside the predicate then compare those.
        //  - Stick to the supported operators inside of #Predicate, not everything works, even things you would expect.
        //

        let full = VaultEncodingConstants.SearchableLevel.full
        let onlyTitle = VaultEncodingConstants.SearchableLevel.onlyTitle
        let titleSearchable = #Predicate<PersistedVaultItem> {
            $0.searchableLevel == full || $0.searchableLevel == onlyTitle
        }

        // Can only search full content if searchable level is full AND the item isn't locked.
        // If it's locked, we shouldn't be able to search the content.
        let notLocked = VaultEncodingConstants.LockState.notLocked
        let contentSearchable = #Predicate<PersistedVaultItem> {
            $0.searchableLevel == full && $0.lockState == notLocked
        }

        let userDescriptionPredicate = #Predicate<PersistedVaultItem> {
            $0.userDescription.localizedStandardContains(query) && titleSearchable.evaluate($0)
        }

        let noteTitlePredicate = #Predicate<PersistedVaultItem> { item in
            item.noteDetails.flatMap {
                $0.title.localizedStandardContains(query) && titleSearchable.evaluate(item)
            } ?? false
        }

        let noteContentsPredicate = #Predicate<PersistedVaultItem> { item in
            item.noteDetails.flatMap {
                $0.contents.localizedStandardContains(query) && contentSearchable.evaluate(item)
            } ?? false
        }

        let codeNamePredicate = #Predicate<PersistedVaultItem> { item in
            item.otpDetails.flatMap {
                $0.accountName.localizedStandardContains(query) && titleSearchable.evaluate(item)
            } ?? false
        }

        let codeIssuerPredicate = #Predicate<PersistedVaultItem> { item in
            item.otpDetails.flatMap {
                $0.issuer.localizedStandardContains(query) && titleSearchable.evaluate(item)
            } ?? false
        }

        let encryptedNoteTitlePredicate = #Predicate<PersistedVaultItem> { item in
            item.encryptedItemDetails.flatMap {
                $0.title.localizedStandardContains(query) && titleSearchable.evaluate(item)
            } ?? false
        }

        let matchesMetadata = #Predicate<PersistedVaultItem> {
            userDescriptionPredicate.evaluate($0)
        }

        let matchesNote = #Predicate<PersistedVaultItem> {
            noteTitlePredicate.evaluate($0) ||
                noteContentsPredicate.evaluate($0)
        }

        let matchesCode = #Predicate<PersistedVaultItem> {
            codeNamePredicate.evaluate($0) ||
                codeIssuerPredicate.evaluate($0)
        }

        let matchesUnencryptedItem = #Predicate<PersistedVaultItem> {
            matchesCode.evaluate($0) || matchesNote.evaluate($0)
        }

        let matchesAnyItem = #Predicate<PersistedVaultItem> {
            matchesUnencryptedItem.evaluate($0) || encryptedNoteTitlePredicate.evaluate($0)
        }

        return #Predicate<PersistedVaultItem> {
            matchesMetadata.evaluate($0) || matchesAnyItem.evaluate($0)
        }
    }
}

// MARK: - VaultStoreWriter

extension PersistedLocalVaultStore: VaultStoreWriter {
    @discardableResult
    public func insert(item: VaultItem.Write) async throws -> Identifier<VaultItem> {
        do {
            let record = try PersistedVaultItemEncoder(currentDate: currentDate).encode(item: item)
            try store(record: record)

            try modelContext.save()
            return Identifier(id: record.id)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    public func update(id: Identifier<VaultItem>, item: VaultItem.Write) async throws {
        do {
            let existing = try fetchVaultItem(id: id)
            let encoder = PersistedVaultItemEncoder(currentDate: currentDate)
            let record = try encoder.encode(item: item, existing: existing.makeRecord())
            try store(record: record)

            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    public func delete(id: Identifier<VaultItem>) async throws {
        do {
            let uuid = id.rawValue
            try modelContext.delete(model: PersistedVaultItem.self, where: #Predicate {
                $0.id == uuid
            })
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}

// MARK: - VaultStoreHOTPIncrementer

extension PersistedLocalVaultStore: VaultStoreHOTPIncrementer {
    public func incrementCounter(id: Identifier<VaultItem>) async throws {
        do {
            let existing = try fetchVaultItem(id: id)
            guard let otpDetails = existing.otpDetails else { throw Error.invalidItem }
            otpDetails.counter.safeIncrement()
            modelContext.insert(otpDetails)

            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}

extension Int64? {
    fileprivate mutating func safeIncrement() {
        switch self {
        case nil: break
        case let .some(val): self = val + 1
        }
    }
}

// MARK: - VaultStoreReorderable

extension PersistedLocalVaultStore: VaultStoreReorderable {
    public func reorder(
        items: Set<Identifier<VaultItem>>,
        to position: VaultReorderingPosition,
    ) async throws {
        do {
            var allItemsDescriptor = FetchDescriptor<PersistedVaultItem>(
                predicate: .true,
                // The same order that users see so the ordering is correct.
                sortBy: sortOrder.vaultItemSortDescriptors,
            )
            allItemsDescriptor.propertiesToFetch = [\.id, \.relativeOrder]
            var allItems = try modelContext.fetch(allItemsDescriptor)
            let originIndexes = items.compactMap { item in allItems.firstIndex(where: { $0.id == item.rawValue }) }
            let indexToMoveTo: Int = try {
                switch position {
                case .start:
                    return 0
                case let .after(id):
                    guard let index = allItems.firstIndex(where: { $0.id == id.rawValue }) else {
                        throw Error.relativeItemNotFound
                    }
                    return index + 1
                }
            }()
            allItems.move(fromOffsets: IndexSet(originIndexes), toOffset: indexToMoveTo)

            // Reorder all the items in their new current order.
            for (index, item) in allItems.enumerated() {
                item.relativeOrder = UInt64(index)
            }

            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}

// MARK: - VaultStoreExporter

extension PersistedLocalVaultStore: VaultStoreExporter {
    public func exportVault(userDescription: String) async throws -> VaultApplicationPayload {
        let allItems: [PersistedVaultItem] = try modelContext.fetch(.all())
        let allTags: [PersistedVaultTag] = try modelContext.fetch(.all())
        let itemDecoder = PersistedVaultItemDecoder()
        let tagDecoder = PersistedVaultTagDecoder()
        return try .init(
            userDescription: userDescription,
            items: allItems.map {
                try itemDecoder.decode(record: $0.makeRecord())
            },
            tags: allTags.map {
                try tagDecoder.decode(record: $0.makeRecord())
            },
        )
    }
}

// MARK: - VaultTagStoreReader

extension PersistedLocalVaultStore: VaultTagStoreReader {
    public func retrieveTags() async throws -> [VaultItemTag] {
        let allTags: [PersistedVaultTag] = try modelContext.fetch(.all(sortBy: [SortDescriptor(\.title)]))
        let decoder = PersistedVaultTagDecoder()
        return try allTags.map {
            try decoder.decode(record: $0.makeRecord())
        }
    }
}

// MARK: - VaultTagStoreWriter

extension PersistedLocalVaultStore: VaultTagStoreWriter {
    @discardableResult
    public func insertTag(item: VaultItemTag.Write) async throws -> Identifier<VaultItemTag> {
        do {
            let record = PersistedVaultTagEncoder().encode(tag: item)
            try store(record: record)

            try modelContext.save()
            return Identifier<VaultItemTag>(id: record.id)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    public func updateTag(id: Identifier<VaultItemTag>, item: VaultItemTag.Write) async throws {
        do {
            let existing = try fetchVaultItemTag(id: id)
            let record = PersistedVaultTagEncoder().encode(tag: item, existing: existing.makeRecord())
            try store(record: record)

            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    public func deleteTag(id: Identifier<VaultItemTag>) async throws {
        do {
            // Delete the tag.
            let uuid = id.id
            try modelContext.delete(model: PersistedVaultTag.self, where: #Predicate {
                $0.id == uuid
            })

            // Then, remove the tag from all items that contain it.
            let tagsPredicate = makeTagsPredicate(matchingTags: [id])
            let fetchDescriptor = FetchDescriptor(predicate: tagsPredicate)
            let allItems: [PersistedVaultItem] = try modelContext.fetch(fetchDescriptor)
            for item in allItems {
                item.tags.removeAll(where: { $0.id == id.id })
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}

// MARK: - VaultStoreImporter

extension PersistedLocalVaultStore: VaultStoreImporter {
    public func importAndMergeVault(payload: VaultApplicationPayload) async throws {
        do {
            let exported = try await exportVault(userDescription: "")
            let itemUpdatedDates = exported.items
                .reduce(into: [Identifier<VaultItem>: Date]()) { partialResult, nextItem in
                    partialResult[nextItem.id] = nextItem.metadata.updated
                }
            let itemsToImport = payload.items.filter {
                // Only import item if it was updated more recently.
                $0.metadata.updated > itemUpdatedDates[$0.id, default: .distantPast]
            }

            let tagEncoder = PersistedVaultTagEncoder()
            for tag in payload.tags {
                let record = tagEncoder.encode(tag: tag.makeWritable(), writeUpdateContext: tag.makeImportingContext())
                try store(record: record)
            }

            let itemEncoder = PersistedVaultItemEncoder(currentDate: currentDate)
            for item in itemsToImport {
                let record = try itemEncoder.encode(
                    item: item.makeWritable(),
                    writeUpdateContext: item.makeImportingContext(),
                )
                try store(record: record)
            }

            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    public func importAndOverrideVault(payload: VaultApplicationPayload) async throws {
        do {
            try await deleteVault()
            let tagEncoder = PersistedVaultTagEncoder()
            for tag in payload.tags {
                let record = tagEncoder.encode(tag: tag.makeWritable(), writeUpdateContext: tag.makeImportingContext())
                try store(record: record)
            }
            let itemEncoder = PersistedVaultItemEncoder(currentDate: currentDate)
            for item in payload.items {
                let record = try itemEncoder.encode(
                    item: item.makeWritable(),
                    writeUpdateContext: item.makeImportingContext(),
                )
                try store(record: record)
            }

            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}

// MARK: - VaultStoreDeleter

extension PersistedLocalVaultStore: VaultStoreDeleter {
    public func deleteVault() async throws {
        do {
            for model in PersistedSchemaLatestVersion.models {
                try modelContext.delete(model: model)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}

// MARK: - VaultStoreKillphraseDeleter

extension PersistedLocalVaultStore: VaultStoreKillphraseDeleter {
    @discardableResult
    public func deleteItems(matchingKillphrase: String, using matcher: any KillphraseMatcher) async -> Bool {
        do {
            guard matchingKillphrase.isNotBlank else { return false }

            // Fetch all items that carry a killphrase digest. We deliberately
            // iterate every candidate (no early exit, no #Predicate equality)
            // so timing does not leak which item matched.
            let predicate: Predicate<PersistedVaultItem> = #Predicate {
                $0.killphraseDigest != nil && $0.killphraseSalt != nil
            }
            let descriptor = FetchDescriptor<PersistedVaultItem>(predicate: predicate)
            let candidates = try modelContext.fetch(descriptor)

            var idsToDelete: [UUID] = []
            for item in candidates {
                guard let salt = item.killphraseSalt, let digest = item.killphraseDigest else { continue }
                if matcher.matches(query: matchingKillphrase, salt: salt, digest: digest) {
                    idsToDelete.append(item.id)
                }
            }
            guard idsToDelete.isEmpty == false else { return false }

            let deletionPredicate: Predicate<PersistedVaultItem> = #Predicate { item in
                idsToDelete.contains(item.id)
            }
            try modelContext.delete(model: PersistedVaultItem.self, where: deletionPredicate)
            try modelContext.save()
            return true
        } catch {
            // Error path must be indistinguishable from "no match" to preserve the
            // killphrase threat model — any signal here (crash, throw, log) is an
            // oracle that confirms phrase validity to an attacker.
            modelContext.rollback()
            return false
        }
    }
}

// MARK: - Killphrase Rehash

extension PersistedLocalVaultStore {
    /// Writes a freshly-computed killphrase digest onto the persisted item
    /// with the given ID. Used by `KillphraseRehashService` during the
    /// V1 → V2 migration's Phase B.
    ///
    /// No-op (without error) if the item no longer exists — the item may
    /// have been deleted between the schema migration and the rehash pass.
    public func applyKillphraseDigest(itemID: UUID, digest: KillphraseDigest) async throws {
        do {
            var descriptor = FetchDescriptor<PersistedVaultItem>(predicate: #Predicate { item in
                item.id == itemID
            })
            descriptor.fetchLimit = 1
            guard let item = try modelContext.fetch(descriptor).first else { return }
            item.killphraseSalt = digest.salt
            item.killphraseDigest = digest.digest
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}

// MARK: - Search Passphrase Rehash

extension PersistedLocalVaultStore {
    /// Writes a freshly-computed search-passphrase digest onto the
    /// persisted item with the given ID. Used by
    /// `SearchPassphraseRehashService` during the V2 → V3 migration's
    /// Phase B.
    ///
    /// No-op (without error) if the item no longer exists.
    public func applySearchPassphraseDigest(itemID: UUID, digest: SearchPassphraseDigest) async throws {
        do {
            var descriptor = FetchDescriptor<PersistedVaultItem>(predicate: #Predicate { item in
                item.id == itemID
            })
            descriptor.fetchLimit = 1
            guard let item = try modelContext.fetch(descriptor).first else { return }
            item.searchPassphraseSalt = digest.salt
            item.searchPassphraseDigest = digest.digest
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}

// MARK: - Helpers

extension PersistedLocalVaultStore {
    /// Stores the item record: updates the stored item with its id in place, or inserts a new one.
    ///
    /// The record's tag ids are resolved to stored tags, and ids that name no stored tag are dropped. Tags inserted
    /// but not yet saved count, so an import can store its tags and then items that carry them.
    ///
    /// An existing item is updated in place rather than replaced by a new model with the same id. SwiftData's
    /// unique-id upsert merges to-many relationships instead of replacing them, so a replacement would keep tags
    /// the record no longer has.
    private func store(record: VaultItemRecord) throws {
        let tagIDs = record.tagIDs
        let tags = try modelContext.fetch(FetchDescriptor<PersistedVaultTag>(predicate: #Predicate {
            tagIDs.contains($0.id)
        }))
        if let existing = try fetchVaultItemIfPresent(id: record.id) {
            existing.apply(record, tags: tags, in: modelContext)
        } else {
            modelContext.insert(PersistedVaultItem(record: record, tags: tags))
        }
    }

    /// Stores the tag record: updates the stored tag with its id in place, keeping the items that carry it, or
    /// inserts a new one.
    private func store(record: VaultTagRecord) throws {
        if let existing = try fetchVaultItemTagIfPresent(id: record.id) {
            existing.apply(record)
        } else {
            modelContext.insert(PersistedVaultTag(record: record))
        }
    }

    private func fetchVaultItemIfPresent(id: UUID) throws -> PersistedVaultItem? {
        var descriptor = FetchDescriptor<PersistedVaultItem>(predicate: #Predicate { item in
            item.id == id
        })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchVaultItemTagIfPresent(id: UUID) throws -> PersistedVaultTag? {
        var descriptor = FetchDescriptor<PersistedVaultTag>(predicate: #Predicate { tag in
            tag.id == id
        })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchVaultItem(id: Identifier<VaultItem>) throws -> PersistedVaultItem {
        guard let existing = try fetchVaultItemIfPresent(id: id.rawValue) else {
            throw Error.modelNotFound
        }
        return existing
    }

    private func fetchVaultItemTag(id: Identifier<VaultItemTag>) throws -> PersistedVaultTag {
        guard let existing = try fetchVaultItemTagIfPresent(id: id.id) else {
            throw Error.modelNotFound
        }
        return existing
    }

    private func fetchHasModelsInStorage<T: PersistentModel>(model _: T.Type) throws -> Bool {
        var itemDescriptor = FetchDescriptor<T>(predicate: .true)
        itemDescriptor.fetchLimit = 1
        let result = try modelContext.fetch(itemDescriptor)
        return result.isNotEmpty
    }
}

// MARK: - Helpers

extension VaultStoreSortOrder {
    fileprivate var vaultItemSortDescriptors: [SortDescriptor<PersistedVaultItem>] {
        switch self {
        case .relativeOrder:
            [
                // The priority is to sort by relative order.
                // This is because this is due to the user's explicit ordering.
                SortDescriptor(\.relativeOrder),
                // If two items have the same relative order, we sort by created date.
                // It's reversed so that newer items appear first.
                SortDescriptor(\.createdDate, order: .reverse),
            ]
        case .createdDate:
            [
                SortDescriptor(\.createdDate),
            ]
        }
    }
}
