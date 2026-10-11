import Foundation
import FoundationExtensions
import VaultCore

public typealias VaultStore = VaultStoreEncryptedItemReplacer & VaultStoreExporter & VaultStoreHOTPIncrementer &
    VaultStoreReader & VaultStoreReorderable & VaultStoreWriter

public protocol VaultStoreReader: Sendable {
    /// Retrieve items matching the given query.
    ///
    /// When `searchPassphraseMatcher` is supplied and `query.filterText` is
    /// non-empty, items with `searchableLevel == .onlyPassphrase` are
    /// additionally returned if the matcher verifies the filter text
    /// against their stored digest.
    func retrieve(
        query: VaultStoreQuery,
        searchPassphraseMatcher: (any SearchPassphraseMatcher)?,
    ) async throws -> VaultRetrievalResult<VaultItem>

    /// Returns a boolean if there is any data in the store at all.
    ///
    /// This checks all items, including hidden and locked ones.
    var hasAnyItems: Bool { get async throws }
}

extension VaultStoreReader {
    /// Convenience overload for callers that have no matcher available
    /// (vault locked, app extension without keychain access, tests).
    /// Passphrase-protected items will not be returned.
    public func retrieve(query: VaultStoreQuery) async throws -> VaultRetrievalResult<VaultItem> {
        try await retrieve(query: query, searchPassphraseMatcher: nil)
    }
}

public protocol VaultStoreWriter: Sendable {
    /// Create a new item in the vault store, based off the provided data.
    ///
    /// The id will be created by the underlying storage layer and returned.
    ///
    /// - Returns: The unique ID of the newly created item.
    @discardableResult
    func insert(item: VaultItem.Write) async throws -> Identifier<VaultItem>

    /// Update the item with the given `id`.
    func update(id: Identifier<VaultItem>, item: VaultItem.Write) async throws

    /// Delete the item with the specific `id`.
    ///
    /// This should have no effect if the item does not exist.
    func delete(id: Identifier<VaultItem>) async throws
}

/// @mockable
public protocol VaultStoreHOTPIncrementer: Sendable {
    func incrementCounter(id: Identifier<VaultItem>) async throws
}

/// @mockable
public protocol VaultStoreEncryptedItemReplacer: Sendable {
    /// Replaces the encrypted item with `id`, if it's still `old`, with `new`: the same item encrypted again, as when
    /// it
    /// moves to a stronger key derivation (VAULT-128). Nothing else about the item changes, not even its dates.
    ///
    /// - Returns: Whether it replaced it: `false` if there's no item with `id`, or it isn't `old` any more, such as
    ///   when it's been edited since.
    func replaceEncryptedItem(id: Identifier<VaultItem>, _ old: EncryptedItem, with new: EncryptedItem) async throws
        -> Bool
}

/// @mockable
public protocol VaultStoreReorderable: Sendable {
    /// Reorder the item with the given `id` to the given position and current view.
    func reorder(
        items: Set<Identifier<VaultItem>>,
        to position: VaultReorderingPosition,
    ) async throws
}

/// @mockable
public protocol VaultStoreExporter: Sendable {
    func exportVault(userDescription: String) async throws -> VaultApplicationPayload
}

/// @mockable
public protocol VaultStoreImporter: Sendable {
    /// Imports the data in the payload without affecting existing data.
    ///
    ///  - note: If there are duplicate items, the most recently edited one will be retained.
    func importAndMergeVault(payload: VaultApplicationPayload) async throws

    /// Imports the data in the payload, deleting existing vault data.
    func importAndOverrideVault(payload: VaultApplicationPayload) async throws
}

/// @mockable
public protocol VaultStoreDeleter: Sendable {
    /// Deletes the entire vault immediately.
    ///
    /// - note: This operation is atomic and will either complete fully or not at all.
    func deleteVault() async throws
}

/// @mockable
public protocol VaultStoreKillphraseDeleter: Sendable {
    /// Deletes items whose stored killphrase digest verifies against the
    /// given query using the supplied matcher.
    ///
    /// - Parameters:
    ///   - matchingKillphrase: The user-entered query (typically the live
    ///     contents of the search bar).
    ///   - matcher: Computes `HMAC(K, salt || query)` per-item and compares
    ///     against the persisted digest in constant time. Must come from
    ///     the unlocked vault key; when the vault is locked, callers
    ///     should skip this call entirely.
    /// - Returns: `true` if any items were deleted, `false` if no items
    ///   matched **or** if an internal error prevented deletion.
    /// - Important: This method intentionally returns the same value on
    ///   "no match" and on internal failure so the killphrase feature does
    ///   not leak phrase validity through error channels. Callers must not
    ///   surface failures via UI, logs, or telemetry.
    @discardableResult
    func deleteItems(matchingKillphrase: String, using matcher: any KillphraseMatcher) async -> Bool
}
