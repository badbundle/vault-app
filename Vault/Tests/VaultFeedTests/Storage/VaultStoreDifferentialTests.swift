import Foundation
import FoundationExtensions
import TestHelpers
import Testing
import VaultCore
@testable import VaultFeed

/// Runs the same random sequence of operations against the SwiftData store and the record store, and checks that
/// they agree at every step: what each operation returns or throws, and what retrieval, tags and export give back
/// afterwards.
///
/// The contract suite covers the behavior someone thought to write a test for; this covers the combinations nobody
/// did. Each seed is a reproducible sequence, and a failure names its seed, step and operation.
struct VaultStoreDifferentialTests {
    /// Compared against the SwiftData store both in memory and on SQLite, as the app stores a vault today.
    @Test(arguments: [VaultStoreEngine.swiftData, .swiftDataSQLite], 0 ..< 40)
    func storesAgreeOnRandomOperations(reference: VaultStoreEngine, seed: UInt64) async throws {
        var harness = try await DifferentialHarness(reference: reference, seed: seed)
        for step in 0 ..< 80 {
            try await harness.runRandomStep(step)
        }
    }
}

// MARK: - Harness

/// Two stores driven in lockstep.
///
/// Items and tags created through a store get ids from that store, so the two stores' ids differ. The harness keeps
/// each item and tag as the pair of ids the stores gave it, hands each store its own ids, and translates the record
/// store's results into the SwiftData store's ids before comparing. Items and tags that arrive by import have the
/// same id in both.
private struct DifferentialHarness {
    private let swiftData: any ContractTestableVaultStore
    private let records: any ContractTestableVaultStore
    private var rng: SeededRandomNumberGenerator
    private let seed: UInt64
    private let clock = SharedMutex(Date(timeIntervalSince1970: 1_700_000_000))
    private var items = [StorePair]()
    private var tags = [StorePair]()
    private var step = 0
    private var operation = ""

    init(reference: VaultStoreEngine, seed: UInt64) async throws {
        self.seed = seed
        rng = SeededRandomNumberGenerator(seed: seed)
        let sortOrder: VaultStoreSortOrder = seed.isMultiple(of: 2) ? .relativeOrder : .createdDate
        swiftData = try await reference.makeStore(sortOrder: sortOrder)
        records = try await VaultStoreEngine.records.makeStore(sortOrder: sortOrder)
        let clock = clock
        let now: @Sendable () -> Date = { clock.get { $0 } }
        await swiftData.updateCurrentDate(now)
        await records.updateCurrentDate(now)
    }

    mutating func runRandomStep(_ step: Int) async throws {
        self.step = step
        clock.modify { $0.addTimeInterval(1) }
        switch Int.random(in: 0 ..< 100, using: &rng) {
        case 0 ..< 18: try await insertItem()
        case 18 ..< 28: try await updateItem()
        case 28 ..< 33: try await deleteItem()
        case 33 ..< 38: try await incrementCounter()
        case 38 ..< 45: try await reorder()
        case 45 ..< 53: try await insertTag()
        case 53 ..< 57: try await updateTag()
        case 57 ..< 61: try await deleteTag()
        case 61 ..< 69: try await importPayload(override: false)
        case 69 ..< 72: try await importPayload(override: true)
        case 72 ..< 73: try await deleteVault()
        case 73 ..< 81: try await deleteMatchingKillphrase()
        case 81 ..< 84: try await corruptItem()
        default: break
        }
        try await expectSameState()
    }
}

// MARK: - Operations

extension DifferentialHarness {
    private mutating func insertItem() async throws {
        let write = makeWrite()
        operation = "insert \(write.description)"
        let swiftDataResult = await Result(asyncCatching: {
            try await swiftData.insert(item: write.materialized(for: .swiftData, tags: tags))
        })
        let recordsResult = await Result(asyncCatching: {
            try await records.insert(item: write.materialized(for: .records, tags: tags))
        })
        try requireSameOutcome(swiftDataResult, recordsResult)
        if case let .success(swiftDataID) = swiftDataResult, case let .success(recordsID) = recordsResult {
            items.append(StorePair(swiftData: swiftDataID.rawValue, records: recordsID.rawValue))
        }
    }

    private mutating func updateItem() async throws {
        let target = pickItem()
        let write = makeWrite(isUpdate: true)
        operation = "update \(target) with \(write.description)"
        try await requireSameOutcome(
            swiftData: { try await swiftData.update(id: .init(id: target.swiftData), item: write.materialized(
                for: .swiftData,
                tags: tags,
            )) },
            records: { try await records.update(id: .init(id: target.records), item: write.materialized(
                for: .records,
                tags: tags,
            )) },
        )
    }

    private mutating func deleteItem() async throws {
        let target = pickItem()
        operation = "delete \(target)"
        try await requireSameOutcome(
            swiftData: { try await swiftData.delete(id: .init(id: target.swiftData)) },
            records: { try await records.delete(id: .init(id: target.records)) },
        )
    }

    private mutating func incrementCounter() async throws {
        let target = pickItem()
        operation = "increment counter of \(target)"
        try await requireSameOutcome(
            swiftData: { try await swiftData.incrementCounter(id: .init(id: target.swiftData)) },
            records: { try await records.incrementCounter(id: .init(id: target.records)) },
        )
    }

    private mutating func reorder() async throws {
        let moving = (0 ..< Int.random(in: 0 ... 3, using: &rng)).map { _ in pickItem() }
        let after: StorePair? = Bool.random(using: &rng) ? nil : pickItem()
        operation = "reorder \(moving) to \(after.map { "after \($0)" } ?? "start")"
        try await requireSameOutcome(
            swiftData: { try await swiftData.reorder(
                items: Set(moving.map { Identifier(id: $0.swiftData) }),
                to: after.map { .after(.init(id: $0.swiftData)) } ?? .start,
            ) },
            records: { try await records.reorder(
                items: Set(moving.map { Identifier(id: $0.records) }),
                to: after.map { .after(.init(id: $0.records)) } ?? .start,
            ) },
        )
    }

    private mutating func insertTag() async throws {
        let write = makeTagWrite()
        operation = "insert tag \(write)"
        let swiftDataResult = await Result(asyncCatching: { try await swiftData.insertTag(item: write) })
        let recordsResult = await Result(asyncCatching: { try await records.insertTag(item: write) })
        try requireSameOutcome(swiftDataResult, recordsResult)
        if case let .success(swiftDataID) = swiftDataResult, case let .success(recordsID) = recordsResult {
            tags.append(StorePair(swiftData: swiftDataID.id, records: recordsID.id))
        }
    }

    private mutating func updateTag() async throws {
        let target = pickTag()
        let write = makeTagWrite()
        operation = "update tag \(target) with \(write)"
        try await requireSameOutcome(
            swiftData: { try await swiftData.updateTag(id: .init(id: target.swiftData), item: write) },
            records: { try await records.updateTag(id: .init(id: target.records), item: write) },
        )
    }

    private mutating func deleteTag() async throws {
        let target = pickTag()
        operation = "delete tag \(target)"
        try await requireSameOutcome(
            swiftData: { try await swiftData.deleteTag(id: .init(id: target.swiftData)) },
            records: { try await records.deleteTag(id: .init(id: target.records)) },
        )
    }

    private mutating func importPayload(override: Bool) async throws {
        let payload = makePayload()
        operation = "\(override ? "override" : "merge") import of \(payload.description)"
        let swiftDataPayload = payload.materialized(for: .swiftData, items: items, tags: tags)
        let recordsPayload = payload.materialized(for: .records, items: items, tags: tags)
        if override {
            try await requireSameOutcome(
                swiftData: { try await swiftData.importAndOverrideVault(payload: swiftDataPayload) },
                records: { try await records.importAndOverrideVault(payload: recordsPayload) },
            )
        } else {
            try await requireSameOutcome(
                swiftData: { try await swiftData.importAndMergeVault(payload: swiftDataPayload) },
                records: { try await records.importAndMergeVault(payload: recordsPayload) },
            )
        }
        // New items and tags in a payload have the same id in both stores.
        items += payload.newItemIDs.map { StorePair(swiftData: $0, records: $0) }
        tags += payload.newTagIDs.map { StorePair(swiftData: $0, records: $0) }
    }

    private mutating func deleteVault() async throws {
        operation = "delete vault"
        try await requireSameOutcome(
            swiftData: { try await swiftData.deleteVault() },
            records: { try await records.deleteVault() },
        )
    }

    private mutating func deleteMatchingKillphrase() async throws {
        let query = Vocabulary.killphraseQueries.randomElement(using: &rng)!
        operation = "delete items matching killphrase \(query.debugDescription)"
        let swiftDataDeleted = await swiftData.deleteItems(matchingKillphrase: query, using: testDigester)
        let recordsDeleted = await records.deleteItems(matchingKillphrase: query, using: testDigester)
        try require(swiftDataDeleted == recordsDeleted, "deleted: \(swiftDataDeleted) vs \(recordsDeleted)")
    }

    /// Stores an OTP algorithm that doesn't exist on an item, so it stops decoding.
    private mutating func corruptItem() async throws {
        let storedIDs = try await swiftData.storedItemIDs()
        let candidates = items.filter { storedIDs.contains($0.swiftData) }
        guard let target = candidates.randomElement(using: &rng) else { return }
        operation = "corrupt \(target)"
        try await swiftData.corruptItemAlgorithm(id: .init(id: target.swiftData))
        try await records.corruptItemAlgorithm(id: .init(id: target.records))
    }
}

// MARK: - Comparing

extension DifferentialHarness {
    /// Checks everything the stores return about their contents.
    private mutating func expectSameState() async throws {
        let swiftDataIDs = try await swiftData.storedItemIDs()
        let recordsIDs = try await records.storedItemIDs()
        try require(swiftDataIDs == Set(recordsIDs.map(translateItemID)), "stored item ids differ")

        let swiftDataHasItems = try await swiftData.hasAnyItems
        let recordsHasItems = try await records.hasAnyItems
        try require(swiftDataHasItems == recordsHasItems, "hasAnyItems differs")

        try await requireSameRetrieval(query: StoreQuery(filterText: nil, filterTags: []), matcher: nil)
        for _ in 0 ..< 3 {
            let query = makeQuery()
            let matcher: SearchPassphraseDigester? = Bool.random(using: &rng) ? searchPassphraseDigester : nil
            try await requireSameRetrieval(query: query, matcher: matcher)
        }

        try await requireSameTags()
        try await requireSameExport()
    }

    private func requireSameRetrieval(query: StoreQuery, matcher: SearchPassphraseDigester?) async throws {
        let swiftDataResult = await Result(asyncCatching: {
            try await swiftData.retrieve(query: query.materialized(for: .swiftData), searchPassphraseMatcher: matcher)
        })
        let recordsResult = await Result(asyncCatching: {
            try await records.retrieve(query: query.materialized(for: .records), searchPassphraseMatcher: matcher)
        })
        let context = "retrieve \(query.description), matcher: \(matcher != nil)"
        try requireSameOutcome(swiftDataResult, recordsResult, context)
        guard case let .success(swiftData) = swiftDataResult, case let .success(records) = recordsResult else { return }
        let translated = records.items.map(translate)
        try require(
            swiftData.items == translated,
            "\(context): items differ, \(firstDifference(swiftData.items, translated))",
        )
        try require(swiftData.errors == records.errors, "\(context): errors differ")
    }

    /// Tags with the same title can come back in either order, so titles are compared in order and the tags as a
    /// set.
    private func requireSameTags() async throws {
        let swiftDataResult = await Result(asyncCatching: { try await swiftData.retrieveTags() })
        let recordsResult = await Result(asyncCatching: { try await records.retrieveTags() })
        try requireSameOutcome(swiftDataResult, recordsResult, "retrieveTags")
        guard case let .success(swiftData) = swiftDataResult, case let .success(records) = recordsResult else { return }
        try require(swiftData.map(\.name) == records.map(\.name), "retrieveTags: title order differs")
        try require(Set(swiftData) == Set(records.map(translate)), "retrieveTags: tags differ")
    }

    /// Exports are compared as sets: the order of an export isn't part of the contract.
    private func requireSameExport() async throws {
        let swiftDataResult =
            await Result(asyncCatching: { try await swiftData.exportVault(userDescription: "export") })
        let recordsResult = await Result(asyncCatching: { try await records.exportVault(userDescription: "export") })
        try requireSameOutcome(swiftDataResult, recordsResult, "exportVault")
        guard case let .success(swiftData) = swiftDataResult, case let .success(records) = recordsResult else { return }
        try require(swiftData.items.count == records.items.count, "exportVault: item counts differ")
        try require(Set(swiftData.items) == Set(records.items.map(translate)), "exportVault: items differ")
        try require(Set(swiftData.tags) == Set(records.tags.map(translate)), "exportVault: tags differ")
    }

    /// Runs the operation on both stores and requires that both succeed or both throw.
    private func requireSameOutcome<T>(
        swiftData: () async throws -> T,
        records: () async throws -> T,
    ) async throws {
        let swiftDataResult = await Result(asyncCatching: swiftData)
        let recordsResult = await Result(asyncCatching: records)
        try requireSameOutcome(swiftDataResult, recordsResult)
    }

    private func requireSameOutcome<T>(
        _ swiftData: Result<T, any Error>,
        _ records: Result<T, any Error>,
        _ context: String = "outcome",
    ) throws {
        switch (swiftData, records) {
        case (.success, .success), (.failure, .failure):
            return
        case let (.success, .failure(error)):
            try require(false, "\(context): only the record store threw (\(error))")
        case let (.failure(error), .success):
            try require(false, "\(context): only the SwiftData store threw (\(error))")
        }
    }

    /// The first pair of values that differ, or the counts if one list is longer, for a failure message.
    private func firstDifference<T: Equatable>(_ swiftData: [T], _ records: [T]) -> String {
        if let (lhs, rhs) = zip(swiftData, records).first(where: { $0 != $1 }) {
            return "SwiftData has \(lhs), records has \(rhs)"
        }
        return "SwiftData has \(swiftData.count), records has \(records.count)"
    }

    private func require(_ condition: Bool, _ message: String) throws {
        try #require(condition, "seed \(seed), step \(step), after \(operation): \(message)")
    }

    // MARK: Translating record store ids

    private func translateItemID(_ id: UUID) -> UUID {
        items.first { $0.records == id }?.swiftData ?? id
    }

    private func translateTagID(_ id: UUID) -> UUID {
        tags.first { $0.records == id }?.swiftData ?? id
    }

    private func translate(_ item: VaultItem) -> VaultItem {
        let metadata = item.metadata
        return VaultItem(
            metadata: .init(
                id: .init(id: translateItemID(metadata.id.rawValue)),
                created: metadata.created,
                updated: metadata.updated,
                relativeOrder: metadata.relativeOrder,
                userDescription: metadata.userDescription,
                tags: Set(metadata.tags.map { Identifier(id: translateTagID($0.id)) }),
                visibility: metadata.visibility,
                searchableLevel: metadata.searchableLevel,
                searchPassphrase: metadata.searchPassphrase,
                killphrase: metadata.killphrase,
                lockState: metadata.lockState,
                color: metadata.color,
                showInQuickType: metadata.showInQuickType,
                previewMode: metadata.previewMode,
            ),
            item: item.item,
        )
    }

    private func translate(_ tag: VaultItemTag) -> VaultItemTag {
        VaultItemTag(id: .init(id: translateTagID(tag.id.id)), name: tag.name, color: tag.color, iconName: tag.iconName)
    }
}

// MARK: - Generating

extension DifferentialHarness {
    /// An existing item, or now and then an id neither store has.
    private mutating func pickItem() -> StorePair {
        if items.isEmpty || Int.random(in: 0 ..< 8, using: &rng) == 0 {
            let unknown = UUID()
            return StorePair(swiftData: unknown, records: unknown)
        }
        return items.randomElement(using: &rng)!
    }

    /// An existing tag, or now and then an id neither store has.
    private mutating func pickTag() -> StorePair {
        if tags.isEmpty || Int.random(in: 0 ..< 8, using: &rng) == 0 {
            let unknown = UUID()
            return StorePair(swiftData: unknown, records: unknown)
        }
        return tags.randomElement(using: &rng)!
    }

    private mutating func pickTagRefs() -> [TagRef] {
        (0 ..< Int.random(in: 0 ... 2, using: &rng)).map { _ in
            if tags.isEmpty || Int.random(in: 0 ..< 6, using: &rng) == 0 {
                .unknown(UUID())
            } else {
                .known(Int.random(in: 0 ..< tags.count, using: &rng))
            }
        }
    }

    private mutating func makeWrite(isUpdate: Bool = false) -> ItemWrite {
        let visibility: VaultItemVisibility = Int.random(in: 0 ..< 10, using: &rng) < 7 ? .always : .onlySearch
        let searchableLevel = [VaultItemSearchableLevel.none, .full, .onlyTitle, .onlyPassphrase]
            .randomElement(using: &rng)!
        return ItemWrite(
            relativeOrder: UInt64.random(in: 0 ... 3, using: &rng),
            userDescription: Vocabulary.words.randomElement(using: &rng)!,
            color: Bool.random(using: &rng) ? nil : VaultItemColor(red: 0.1, green: 0.2, blue: 0.3),
            payload: makePayloadItem(),
            tags: pickTagRefs(),
            visibility: visibility,
            searchableLevel: searchableLevel,
            searchPassphraseUpdate: makeSearchPassphraseUpdate(isUpdate: isUpdate),
            killphraseUpdate: makeKillphraseUpdate(isUpdate: isUpdate),
            lockState: Bool.random(using: &rng) ? .notLocked : .lockedWithNativeSecurity,
            showInQuickType: Bool.random(using: &rng),
            previewMode: NotePreviewMode.allCases.randomElement(using: &rng)!,
        )
    }

    private mutating func makePayloadItem() -> VaultItem.Payload {
        let title = Vocabulary.words.randomElement(using: &rng)!
        switch Int.random(in: 0 ..< 100, using: &rng) {
        case 0 ..< 40:
            let type: OTPAuthType = Bool.random(using: &rng)
                ? .totp(period: 30)
                : .hotp(counter: UInt64.random(in: 0 ... 1000, using: &rng))
            return .otpCode(anyOTPAuthCode(
                type: type,
                accountName: Vocabulary.words.randomElement(using: &rng)!,
                issuerName: title,
            ))
        case 40 ..< 75:
            return .secureNote(anySecureNote(
                title: title,
                contents: Vocabulary.words.shuffled(using: &rng).prefix(3).joined(separator: " "),
                format: Bool.random(using: &rng) ? .plain : .markdown,
            ))
        case 75 ..< 97:
            return .encryptedItem(anyEncryptedItem(title: title))
        default:
            // Never storable: both stores must refuse it.
            return .recoveryPhrase(anyRecoveryPhrase(title: title))
        }
    }

    private mutating func makeKillphraseUpdate(isUpdate: Bool) -> VaultItem.KillphraseUpdate {
        switch Int.random(in: 0 ..< 10, using: &rng) {
        case 0 ..< 3: .set(testDigester.makeDigest(phrase: Vocabulary.killphrases.randomElement(using: &rng)!))
        case 3 ..< 6 where isUpdate: .unchanged
        default: .clear
        }
    }

    private mutating func makeSearchPassphraseUpdate(isUpdate: Bool) -> VaultItem.SearchPassphraseUpdate {
        switch Int.random(in: 0 ..< 10, using: &rng) {
        case 0 ..< 4: .set(searchPassphraseDigester.makeDigest(
                phrase: Vocabulary.searchPassphrases.randomElement(using: &rng)!,
            ))
        case 4 ..< 7 where isUpdate: .unchanged
        default: .clear
        }
    }

    private mutating func makeTagWrite() -> VaultItemTag.Write {
        VaultItemTag.Write(
            name: Vocabulary.tagNames.randomElement(using: &rng)!,
            color: Bool.random(using: &rng) ? .tagDefault : VaultItemColor(red: 0.4, green: 0.5, blue: 0.6),
            iconName: Bool.random(using: &rng) ? VaultItemTag.defaultIconName : "star.fill",
        )
    }

    private mutating func makeQuery() -> StoreQuery {
        let text: String? = switch Int.random(in: 0 ..< 10, using: &rng) {
        case 0: nil
        case 1: ""
        default: Vocabulary.searchQueries.randomElement(using: &rng)!
        }
        let filterTags = (0 ..< Int.random(in: 0 ... 2, using: &rng)).map { _ in pickTag() }
        return StoreQuery(filterText: text, filterTags: filterTags)
    }

    /// A payload of new items and tags, and re-imports of existing ones with newer or older dates.
    private mutating func makePayload() -> Payload {
        let now = clock.get { $0 }
        var payload = Payload()
        for _ in 0 ..< Int.random(in: 0 ... 3, using: &rng) {
            if tags.isEmpty || Bool.random(using: &rng) {
                let id = UUID()
                payload.tags.append(PayloadTag(ref: .new(id), write: makeTagWrite()))
                payload.newTagIDs.append(id)
            } else {
                payload.tags.append(PayloadTag(
                    ref: .known(Int.random(in: 0 ..< tags.count, using: &rng)),
                    write: makeTagWrite(),
                ))
            }
        }
        for index in 0 ..< Int.random(in: 0 ... 4, using: &rng) {
            var write = makeWrite()
            if case .recoveryPhrase = write.payload {
                // Backups never carry a plaintext recovery phrase.
                write.payload = .secureNote(anySecureNote(title: "note"))
            }
            if let newTagID = payload.newTagIDs.randomElement(using: &rng), Bool.random(using: &rng) {
                // A tag that arrives in the same payload.
                write.tags.append(.unknown(newTagID))
            }
            // Distinct, non-integral dates, so no two items ever sort the same.
            let created = now.addingTimeInterval(-Double(index + 1) * 1000 - .random(in: 0.1 ..< 0.9, using: &rng))
            let updated = now.addingTimeInterval(.random(in: -5000 ..< 5000, using: &rng))
            if items.isEmpty || Bool.random(using: &rng) {
                let id = UUID()
                payload.items.append(PayloadItem(ref: .new(id), write: write, created: created, updated: updated))
                payload.newItemIDs.append(id)
            } else {
                payload.items.append(PayloadItem(
                    ref: .known(Int.random(in: 0 ..< items.count, using: &rng)),
                    write: write,
                    created: created,
                    updated: updated,
                ))
            }
        }
        return payload
    }
}

// MARK: - Values

/// The ids a store-created item or tag has in each store.
private struct StorePair: CustomStringConvertible, Sendable {
    var swiftData: UUID
    var records: UUID

    var description: String {
        let swiftDataID = swiftData.uuidString.prefix(8)
        return swiftData == records ? "\(swiftDataID)" : "\(swiftDataID)/\(records.uuidString.prefix(8))"
    }
}

private enum StoreSide {
    case swiftData, records

    func pick(_ pair: StorePair) -> UUID {
        switch self {
        case .swiftData: pair.swiftData
        case .records: pair.records
        }
    }
}

private enum TagRef {
    case known(Int)
    case unknown(UUID)

    func id(for side: StoreSide, tags: [StorePair]) -> UUID {
        switch self {
        case let .known(index): side.pick(tags[index])
        case let .unknown(id): id
        }
    }
}

/// An item or tag in a payload: a new one with its id, or an existing one.
private enum PayloadRef {
    case new(UUID)
    case known(Int)

    func id(for side: StoreSide, in pairs: [StorePair]) -> UUID {
        switch self {
        case let .new(id): id
        case let .known(index): side.pick(pairs[index])
        }
    }
}

/// A write, with its tags given independently of either store's ids.
private struct ItemWrite: CustomStringConvertible {
    var relativeOrder: UInt64
    var userDescription: String
    var color: VaultItemColor?
    var payload: VaultItem.Payload
    var tags: [TagRef]
    var visibility: VaultItemVisibility
    var searchableLevel: VaultItemSearchableLevel
    var searchPassphraseUpdate: VaultItem.SearchPassphraseUpdate
    var killphraseUpdate: VaultItem.KillphraseUpdate
    var lockState: VaultItemLockState
    var showInQuickType: Bool
    var previewMode: NotePreviewMode

    var description: String {
        let kind = switch payload {
        case .otpCode: "OTP"
        case .secureNote: "note"
        case .encryptedItem: "encrypted item"
        case .recoveryPhrase: "plaintext recovery phrase"
        }
        return "\(kind) \(userDescription.debugDescription), \(visibility), \(searchableLevel), order \(relativeOrder)"
    }

    func materialized(for side: StoreSide, tags storeTags: [StorePair]) -> VaultItem.Write {
        VaultItem.Write(
            relativeOrder: relativeOrder,
            userDescription: userDescription,
            color: color,
            item: payload,
            tags: Set(tags.map { Identifier(id: $0.id(for: side, tags: storeTags)) }),
            visibility: visibility,
            searchableLevel: searchableLevel,
            searchPassphraseUpdate: searchPassphraseUpdate,
            killphraseUpdate: killphraseUpdate,
            lockState: lockState,
            showInQuickType: showInQuickType,
            previewMode: previewMode,
        )
    }
}

private struct StoreQuery: CustomStringConvertible {
    var filterText: String?
    var filterTags: [StorePair]

    var description: String {
        "text \(filterText.debugDescription), tags \(filterTags)"
    }

    func materialized(for side: StoreSide) -> VaultStoreQuery {
        VaultStoreQuery(filterText: filterText, filterTags: Set(filterTags.map { Identifier(id: side.pick($0)) }))
    }
}

private struct PayloadTag {
    var ref: PayloadRef
    var write: VaultItemTag.Write
}

private struct PayloadItem {
    var ref: PayloadRef
    var write: ItemWrite
    var created: Date
    var updated: Date
}

private struct Payload: CustomStringConvertible {
    var tags = [PayloadTag]()
    var items = [PayloadItem]()
    var newTagIDs = [UUID]()
    var newItemIDs = [UUID]()

    var description: String {
        "\(items.count) items (\(newItemIDs.count) new), \(tags.count) tags (\(newTagIDs.count) new)"
    }

    func materialized(for side: StoreSide, items storeItems: [StorePair], tags storeTags: [StorePair])
        -> VaultApplicationPayload
    {
        VaultApplicationPayload(
            userDescription: "payload",
            items: items.map { item in
                let write = item.write.materialized(for: side, tags: storeTags)
                return VaultItem(
                    metadata: .init(
                        id: .init(id: item.ref.id(for: side, in: storeItems)),
                        created: item.created,
                        updated: item.updated,
                        relativeOrder: write.relativeOrder,
                        userDescription: write.userDescription,
                        tags: write.tags,
                        visibility: write.visibility,
                        searchableLevel: write.searchableLevel,
                        searchPassphrase: item.write.searchPassphraseUpdate.digest,
                        killphrase: item.write.killphraseUpdate.digest,
                        lockState: write.lockState,
                        color: write.color,
                        showInQuickType: write.showInQuickType,
                        previewMode: write.previewMode,
                    ),
                    item: write.item,
                )
            },
            tags: tags.map { tag in
                VaultItemTag(
                    id: .init(id: tag.ref.id(for: side, in: storeTags)),
                    name: tag.write.name,
                    color: tag.write.color,
                    iconName: tag.write.iconName,
                )
            },
        )
    }
}

extension Result where Failure == any Error {
    fileprivate init(asyncCatching body: () async throws -> Success) async {
        do {
            self = try await .success(body())
        } catch {
            self = .failure(error)
        }
    }
}

extension VaultItem.KillphraseUpdate {
    fileprivate var digest: KillphraseDigest? {
        if case let .set(digest) = self {
            digest
        } else {
            nil
        }
    }
}

extension VaultItem.SearchPassphraseUpdate {
    fileprivate var digest: SearchPassphraseDigest? {
        if case let .set(digest) = self {
            digest
        } else {
            nil
        }
    }
}

/// Text chosen so that search, sorting and matching meet case, diacritics, width, ligatures and scripts that
/// compare in interesting ways.
private enum Vocabulary {
    static let words = [
        "", "Alpha", "alpha bank", "Café", "CAFE", "cafe latte", "Zoë", "zoe", "Straße", "strasse", "東京", "tokyo",
        "Bank of Mars", "ﬁle", "file", "ＢＡＮＫ", "İstanbul", "istanbul", "naïve", "NAIVE",
    ]
    static let tagNames = ["Work", "work", "Écoles", "ecoles", "Zebra", "apple", "Apple", "10 things", "9 things", ""]
    static let searchQueries = [
        "alpha", "ALPHA", "caf", "café", "CAFÉ", "zoe", "Zoë", "strasse", "Straße", "ss", "東京", "京", "bank", "ＢＡＮＫ",
        "fi", "file", "istanbul", "İ", "naive", "x", " ", "a", "open sesame", "OPEN SESAME", "hidden",
    ]
    static let killphrases = ["red", "blue", "green"]
    static let killphraseQueries = ["red", " red ", "RED", "blue", "", " ", "\n", "purple"]
    static let searchPassphrases = ["open sesame", "hidden"]
}

private let searchPassphraseDigester: SearchPassphraseDigester = {
    // swiftlint:disable:next force_try
    let key = try! KeyData<32>(data: Data(repeating: 1, count: 32))
    return SearchPassphraseDigester(key: key)
}()

/// SplitMix64: small, fast and reproducible from a seed.
private struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
