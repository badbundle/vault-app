import Foundation
import FoundationExtensions

/// A whole vault as plain records.
struct VaultRecordState: Equatable, Sendable {
    /// Items in the order they were first stored. Retrieval sorts them; exports keep this order.
    var items: [VaultItemRecord]
    /// Tags in the order they were first stored.
    var tags: [VaultTagRecord]

    static let empty = VaultRecordState(items: [], tags: [])
}

/// A vault store that holds the whole vault in memory as `VaultItemRecord`s and `VaultTagRecord`s.
///
/// It implements every vault store protocol with the same behavior as `PersistedLocalVaultStore`, down to the
/// quirks. `VaultStoreContractTests` run one suite against both stores, and `VaultStoreDifferentialTests` run random
/// sequences of operations on both and compare every result. This is the store that holds an unlocked encrypted
/// vault (see `docs/on-device-encryption.md`).
///
/// Every change builds the new state from the current one and only then replaces it, so a change that fails part
/// way through leaves the store exactly as it was.
actor RecordVaultStore {
    enum Error: Swift.Error, Equatable {
        case itemNotFound
        case tagNotFound
        case relativeItemNotFound
        case invalidItem
    }

    /// The stored vault.
    ///
    /// Only this store's operations should change it. Tests also set it directly, to reach states the operations
    /// can't produce, such as a record that doesn't decode.
    var state: VaultRecordState

    /// The order items are retrieved and reordered in, as for `PersistedLocalVaultStore.sortOrder`.
    var sortOrder: VaultStoreSortOrder

    /// The current time, for the created and updated dates of writes. Tests set it to make dates predictable.
    var currentDate: @Sendable () -> Date

    init(
        state: VaultRecordState = .empty,
        sortOrder: VaultStoreSortOrder = .relativeOrder,
        currentDate: @escaping @Sendable () -> Date = { Date() },
    ) {
        self.state = state
        self.sortOrder = sortOrder
        self.currentDate = currentDate
    }
}

// MARK: - VaultStoreReader

extension RecordVaultStore: VaultStoreReader {
    var hasAnyItems: Bool {
        state.items.isNotEmpty
    }

    func retrieve(
        query: VaultStoreQuery,
        searchPassphraseMatcher: (any SearchPassphraseMatcher)?,
    ) async throws -> VaultRetrievalResult<VaultItem> {
        var passphraseMatchIDs = Set<UUID>()
        if let filterText = query.filterText, filterText.isNotEmpty, let matcher = searchPassphraseMatcher {
            passphraseMatchIDs = searchPassphraseMatchIDs(query: filterText, matcher: matcher)
        }
        // As in the SwiftData store, an item whose passphrase matches is returned whatever the tag filter says.
        let matching = state.items.filter { record in
            matches(record, query: query) || passphraseMatchIDs.contains(record.id)
        }
        return .collectFrom(records: sortedForRetrieval(matching))
    }

    /// The ids of `onlyPassphrase` items whose stored digest verifies against `query`.
    ///
    /// Checks every candidate, with no early exit, so the time taken doesn't reveal which item matched.
    private func searchPassphraseMatchIDs(query: String, matcher: any SearchPassphraseMatcher) -> Set<UUID> {
        let onlyPassphrase = VaultEncodingConstants.SearchableLevel.onlyPassphrase
        var ids = Set<UUID>()
        for record in state.items where record.searchableLevel == onlyPassphrase {
            guard let salt = record.searchPassphraseSalt, let digest = record.searchPassphraseDigest else { continue }
            if matcher.matches(query: query, salt: salt, digest: digest) {
                ids.insert(record.id)
            }
        }
        return ids
    }

    private func matches(_ record: VaultItemRecord, query: VaultStoreQuery) -> Bool {
        guard hasEveryTag(record, tags: query.filterTags) else { return false }
        if let filterText = query.filterText, filterText.isNotEmpty {
            // Searching shows every item that matches, whatever its visibility.
            return matchesSearch(record, text: filterText)
        } else {
            return record.visibility == VaultEncodingConstants.Visibility.always
        }
    }

    /// Whether the item carries every one of `tags`.
    private func hasEveryTag(_ record: VaultItemRecord, tags: Set<Identifier<VaultItemTag>>) -> Bool {
        tags.allSatisfy { record.tagIDs.contains($0.id) }
    }

    private func matchesSearch(_ record: VaultItemRecord, text: String) -> Bool {
        let searchableLevel = record.searchableLevel
        let titleSearchable = searchableLevel == VaultEncodingConstants.SearchableLevel.full ||
            searchableLevel == VaultEncodingConstants.SearchableLevel.onlyTitle
        // A locked item's contents are never searchable. An item stored without a lock state counts as locked
        // here, as it does in the SwiftData store's query.
        let contentSearchable = searchableLevel == VaultEncodingConstants.SearchableLevel.full &&
            record.lockState == VaultEncodingConstants.LockState.notLocked

        if titleSearchable, contains(record.userDescription, text) {
            return true
        }
        if let note = record.noteDetails {
            if titleSearchable, contains(note.title, text) {
                return true
            }
            if contentSearchable, contains(note.contents, text) {
                return true
            }
        }
        if let otp = record.otpDetails, titleSearchable {
            if contains(otp.accountName, text) || contains(otp.issuer, text) {
                return true
            }
        }
        if let encrypted = record.encryptedItemDetails, titleSearchable {
            if contains(encrypted.title, text) {
                return true
            }
        }
        return false
    }

    /// Whether `text` contains `query` the way the SwiftData store's `localizedStandardContains` predicate decides
    /// it: ignoring case, diacritics and character width.
    ///
    /// Swift's own `localizedStandardContains` doesn't ignore width, so searching "bank" wouldn't find "ＢＡＮＫ"
    /// here when it does in the SwiftData store.
    private func contains(_ text: String, _ query: String) -> Bool {
        text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) != nil
    }

    /// The items in the order the user sees them, for `sortOrder`.
    ///
    /// Items that sort the same stay in the order they were first stored, so the result is always the same.
    private func sortedForRetrieval(_ records: [VaultItemRecord]) -> [VaultItemRecord] {
        let sorted = records.enumerated().sorted { lhs, rhs in
            switch sortOrder {
            case .relativeOrder:
                if lhs.element.relativeOrder != rhs.element.relativeOrder {
                    return lhs.element.relativeOrder < rhs.element.relativeOrder
                }
                // Newer items first among items with the same relative order.
                if lhs.element.createdDate != rhs.element.createdDate {
                    return lhs.element.createdDate > rhs.element.createdDate
                }
            case .createdDate:
                if lhs.element.createdDate != rhs.element.createdDate {
                    return lhs.element.createdDate < rhs.element.createdDate
                }
            }
            return lhs.offset < rhs.offset
        }
        return sorted.map(\.element)
    }
}

// MARK: - VaultStoreWriter

extension RecordVaultStore: VaultStoreWriter {
    @discardableResult
    func insert(item: VaultItem.Write) async throws -> Identifier<VaultItem> {
        var newState = state
        let record = try PersistedVaultItemEncoder(currentDate: currentDate).encode(item: item)
        newState.upsert(record)
        commit(newState)
        return Identifier(id: record.id)
    }

    func update(id: Identifier<VaultItem>, item: VaultItem.Write) async throws {
        var newState = state
        guard let existing = newState.items.first(where: { $0.id == id.rawValue }) else {
            throw Error.itemNotFound
        }
        let record = try PersistedVaultItemEncoder(currentDate: currentDate).encode(item: item, existing: existing)
        newState.upsert(record)
        commit(newState)
    }

    func delete(id: Identifier<VaultItem>) async throws {
        var newState = state
        newState.items.removeAll { $0.id == id.rawValue }
        commit(newState)
    }
}

// MARK: - VaultStoreHOTPIncrementer

extension RecordVaultStore: VaultStoreHOTPIncrementer {
    /// Advances the stored counter of an OTP item. A code with no counter (a TOTP code) is left as it is, and the
    /// item's updated date doesn't change, as in the SwiftData store.
    func incrementCounter(id: Identifier<VaultItem>) async throws {
        var newState = state
        guard let index = newState.items.firstIndex(where: { $0.id == id.rawValue }) else {
            throw Error.itemNotFound
        }
        guard var otp = newState.items[index].otpDetails else {
            throw Error.invalidItem
        }
        otp.counter = otp.counter.map { $0 + 1 }
        newState.items[index].otpDetails = otp
        commit(newState)
    }
}

// MARK: - VaultStoreReorderable

extension RecordVaultStore: VaultStoreReorderable {
    /// Moves the items to the position, then renumbers every item's relative order from 0 in the resulting order,
    /// as the SwiftData store does.
    func reorder(items: Set<Identifier<VaultItem>>, to position: VaultReorderingPosition) async throws {
        var ordered = sortedForRetrieval(state.items)
        let movingIDs = items.reducedToSet(\.rawValue)
        let destination = switch position {
        case .start:
            0
        case let .after(id):
            if let index = ordered.firstIndex(where: { $0.id == id.rawValue }) {
                index + 1
            } else {
                throw Error.relativeItemNotFound
            }
        }
        ordered.moveSubranges(ordered.indices(where: { movingIDs.contains($0.id) }), to: destination)

        var newState = state
        let relativeOrders = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($1.id, UInt64($0)) })
        for index in newState.items.indices {
            newState.items[index].relativeOrder = relativeOrders[newState.items[index].id] ?? 0
        }
        commit(newState)
    }
}

// MARK: - VaultStoreExporter

extension RecordVaultStore: VaultStoreExporter {
    /// Every item and tag, in the order they were first stored. Throws if any item doesn't decode.
    func exportVault(userDescription: String) async throws -> VaultApplicationPayload {
        let itemDecoder = PersistedVaultItemDecoder()
        let tagDecoder = PersistedVaultTagDecoder()
        return try VaultApplicationPayload(
            userDescription: userDescription,
            items: state.items.map { try itemDecoder.decode(record: $0) },
            tags: state.tags.map { try tagDecoder.decode(record: $0) },
        )
    }
}

// MARK: - VaultTagStoreReader

extension RecordVaultStore: VaultTagStoreReader {
    /// Every tag, sorted by title as the SwiftData store sorts them (localized standard order).
    func retrieveTags() async throws -> [VaultItemTag] {
        let decoder = PersistedVaultTagDecoder()
        let sorted = state.tags.enumerated().sorted { lhs, rhs in
            let comparison = lhs.element.title.localizedStandardCompare(rhs.element.title)
            if comparison != .orderedSame {
                return comparison == .orderedAscending
            }
            return lhs.offset < rhs.offset
        }
        return try sorted.map { try decoder.decode(record: $0.element) }
    }
}

// MARK: - VaultTagStoreWriter

extension RecordVaultStore: VaultTagStoreWriter {
    @discardableResult
    func insertTag(item: VaultItemTag.Write) async throws -> Identifier<VaultItemTag> {
        var newState = state
        let record = PersistedVaultTagEncoder().encode(tag: item)
        newState.upsert(record)
        commit(newState)
        return Identifier(id: record.id)
    }

    func updateTag(id: Identifier<VaultItemTag>, item: VaultItemTag.Write) async throws {
        var newState = state
        guard let existing = newState.tags.first(where: { $0.id == id.id }) else {
            throw Error.tagNotFound
        }
        newState.upsert(PersistedVaultTagEncoder().encode(tag: item, existing: existing))
        commit(newState)
    }

    /// Deletes the tag and removes it from every item that carries it. Does nothing if there's no such tag.
    func deleteTag(id: Identifier<VaultItemTag>) async throws {
        var newState = state
        newState.tags.removeAll { $0.id == id.id }
        for index in newState.items.indices {
            newState.items[index].tagIDs.remove(id.id)
        }
        commit(newState)
    }
}

// MARK: - VaultStoreImporter

extension RecordVaultStore: VaultStoreImporter {
    /// Imports every tag in the payload, and each item that's newer than the stored item with its id.
    ///
    /// Throws, changing nothing, if a stored item doesn't decode, because its updated date can't be compared.
    func importAndMergeVault(payload: VaultApplicationPayload) async throws {
        let exported = try await exportVault(userDescription: "")
        let storedUpdatedDates = exported.items.reduce(into: [Identifier<VaultItem>: Date]()) { dates, item in
            dates[item.id] = item.metadata.updated
        }
        let itemsToImport = payload.items.filter {
            $0.metadata.updated > storedUpdatedDates[$0.id, default: .distantPast]
        }

        var newState = state
        try newState.importing(tags: payload.tags, items: itemsToImport, currentDate: currentDate)
        commit(newState)
    }

    /// Replaces the whole vault with the payload.
    ///
    /// The new vault is built in full before it replaces the old one, so a failure leaves the stored vault as it
    /// was.
    func importAndOverrideVault(payload: VaultApplicationPayload) async throws {
        var newState = VaultRecordState.empty
        try newState.importing(tags: payload.tags, items: payload.items, currentDate: currentDate)
        commit(newState)
    }
}

// MARK: - VaultStoreDeleter

extension RecordVaultStore: VaultStoreDeleter {
    func deleteVault() async throws {
        commit(.empty)
    }
}

// MARK: - VaultStoreKillphraseDeleter

extension RecordVaultStore: VaultStoreKillphraseDeleter {
    @discardableResult
    func deleteItems(matchingKillphrase: String, using matcher: any KillphraseMatcher) async -> Bool {
        guard matchingKillphrase.isNotBlank else { return false }

        // Check every item that carries a killphrase, with no early exit, so the time taken doesn't reveal which
        // item matched.
        var idsToDelete = Set<UUID>()
        for record in state.items {
            guard let salt = record.killphraseSalt, let digest = record.killphraseDigest else { continue }
            if matcher.matches(query: matchingKillphrase, salt: salt, digest: digest) {
                idsToDelete.insert(record.id)
            }
        }
        guard idsToDelete.isNotEmpty else { return false }

        var newState = state
        newState.items.removeAll { idsToDelete.contains($0.id) }
        commit(newState)
        return true
    }
}

// MARK: - Helpers

extension RecordVaultStore {
    private func commit(_ newState: VaultRecordState) {
        state = newState
    }
}

extension VaultRecordState {
    /// Stores the item, replacing a stored item with the same id in place, as the SwiftData store's unique id
    /// does. Tag ids that name no stored tag are dropped.
    mutating func upsert(_ record: VaultItemRecord) {
        var record = record
        let storedTagIDs = tags.reducedToSet(\.id)
        record.tagIDs.formIntersection(storedTagIDs)
        if let index = items.firstIndex(where: { $0.id == record.id }) {
            items[index] = record
        } else {
            items.append(record)
        }
    }

    /// Stores the tag, replacing a stored tag with the same id in place.
    mutating func upsert(_ record: VaultTagRecord) {
        if let index = tags.firstIndex(where: { $0.id == record.id }) {
            tags[index] = record
        } else {
            tags.append(record)
        }
    }

    /// Stores imported tags, then imported items, keeping their ids and dates. Tags come first so the items can
    /// carry them.
    mutating func importing(
        tags importedTags: [VaultItemTag],
        items importedItems: [VaultItem],
        currentDate: @escaping @Sendable () -> Date,
    ) throws {
        let tagEncoder = PersistedVaultTagEncoder()
        for tag in importedTags {
            upsert(tagEncoder.encode(tag: tag.makeWritable(), writeUpdateContext: tag.makeImportingContext()))
        }
        let itemEncoder = PersistedVaultItemEncoder(currentDate: currentDate)
        for item in importedItems {
            try upsert(itemEncoder.encode(item: item.makeWritable(), writeUpdateContext: item.makeImportingContext()))
        }
    }
}
