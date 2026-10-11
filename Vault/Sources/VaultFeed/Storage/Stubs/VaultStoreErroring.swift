import Foundation
import FoundationExtensions

/// A vault store that always errors on every method call.
@MainActor
public final class VaultStoreErroring: VaultStore, VaultTagStoreReader, VaultTagStoreWriter {
    public var error: any Error
    public init(error: any Error) {
        self.error = error
    }

    public var retrieveQueryCalled: (VaultStoreQuery) -> Void = { _ in }
    public func retrieve(
        query: VaultStoreQuery,
        searchPassphraseMatcher _: (any SearchPassphraseMatcher)?,
    ) async throws -> VaultRetrievalResult<VaultItem> {
        retrieveQueryCalled(query)
        throw error
    }

    public var hasAnyItems: Bool {
        get async throws {
            throw error
        }
    }

    public func insert(item _: VaultItem.Write) async throws -> Identifier<VaultItem> {
        throw error
    }

    public func update(id _: Identifier<VaultItem>, item _: VaultItem.Write) async throws {
        throw error
    }

    public func delete(id _: Identifier<VaultItem>) async throws {
        throw error
    }

    public func reorder(
        items _: Set<Identifier<VaultItem>>,
        to _: VaultReorderingPosition,
    ) async throws {
        throw error
    }

    public func exportVault(userDescription _: String) async throws -> VaultApplicationPayload {
        throw error
    }

    public func retrieveTags() async throws -> [VaultItemTag] {
        throw error
    }

    public func deleteTag(id _: Identifier<VaultItemTag>) async throws {
        throw error
    }

    public func insertTag(item _: VaultItemTag.Write) async throws -> Identifier<VaultItemTag> {
        throw error
    }

    public func updateTag(id _: Identifier<VaultItemTag>, item _: VaultItemTag.Write) async throws {
        throw error
    }

    public func incrementCounter(id _: Identifier<VaultItem>) async throws {
        throw error
    }

    public func replaceEncryptedItem(
        id _: Identifier<VaultItem>,
        _: EncryptedItem,
        with _: EncryptedItem,
    ) async throws -> Bool {
        throw error
    }
}
