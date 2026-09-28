import Foundation
import FoundationExtensions

/// A vault store where return values can be easily stubbed for testing or
/// other instances where we don't need a fully functional store.
///
/// This should be able to be used in place of any full `VaultStore`.
@MainActor
public final class VaultStoreStub: VaultStore {
    public init() {}

    public enum CalledMethod: Equatable, Hashable {
        case retrieve
        case insert
        case update
        case delete
        case export
        case reorder
        case retrieveTags
        case insertTag
        case updateTag
        case deleteTag
    }

    public private(set) var calledMethods: [CalledMethod] = []

    public private(set) var retrieveCallCount = 0
    public var retrieveHandler: (VaultStoreQuery) throws -> VaultRetrievalResult<VaultItem> = { _ in .empty() }
    public func retrieve(
        query: VaultStoreQuery,
        searchPassphraseMatcher _: (any SearchPassphraseMatcher)?,
    ) async throws -> VaultRetrievalResult<VaultItem> {
        calledMethods.append(.retrieve)
        retrieveCallCount += 1
        return try retrieveHandler(query)
    }

    public private(set) var hasAnyItemsCallCount = 0
    public var hasAnyItemsHandler: () throws -> Bool = { true }
    public var hasAnyItems: Bool {
        get async throws {
            hasAnyItemsCallCount += 1
            return try hasAnyItemsHandler()
        }
    }

    public private(set) var insertCallCount = 0
    public var insertHandler: (VaultItem.Write) throws -> Identifier<VaultItem> = { _ in .new() }
    public func insert(item: VaultItem.Write) async throws -> Identifier<VaultItem> {
        calledMethods.append(.insert)
        insertCallCount += 1
        return try insertHandler(item)
    }

    public private(set) var updateCallCount = 0
    public var updateHandler: (Identifier<VaultItem>, VaultItem.Write) throws -> Void = { _, _ in }
    public func update(id: Identifier<VaultItem>, item: VaultItem.Write) async throws {
        calledMethods.append(.update)
        updateCallCount += 1
        try updateHandler(id, item)
    }

    public private(set) var deleteCallCount = 0
    public var deleteHandler: (Identifier<VaultItem>) throws -> Void = { _ in }
    public func delete(id: Identifier<VaultItem>) async throws {
        calledMethods.append(.delete)
        deleteCallCount += 1
        try deleteHandler(id)
    }

    public private(set) var exportVaultCallCount = 0
    public var exportVaultHandler: (String) throws -> VaultApplicationPayload = { _ in
        VaultApplicationPayload(userDescription: "any", items: [], tags: [])
    }

    public func exportVault(userDescription: String) async throws -> VaultApplicationPayload {
        calledMethods.append(.export)
        exportVaultCallCount += 1
        return try exportVaultHandler(userDescription)
    }

    public private(set) var reorderCallCount = 0
    public var reorderHandler: (Set<Identifier<VaultItem>>, VaultReorderingPosition) throws -> Void = { _, _ in }
    public func reorder(
        items: Set<Identifier<VaultItem>>,
        to position: VaultReorderingPosition,
    ) async throws {
        calledMethods.append(.reorder)
        reorderCallCount += 1
        try reorderHandler(items, position)
    }

    public private(set) var incrementCounterCallCount = 0
    public private(set) var incrementCounterArgValues = [Identifier<VaultItem>]()
    public func incrementCounter(id: Identifier<VaultItem>) async throws {
        incrementCounterCallCount += 1
        incrementCounterArgValues.append(id)
    }
}

// MARK: - Helpers

extension VaultStoreStub {
    public static var empty: VaultStoreStub {
        .init()
    }
}
