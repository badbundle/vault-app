import Foundation
import FoundationExtensions
import VaultCore

/// The plain store, as an app extension reads and writes it: only while the vault is still in it.
///
/// An extension can't recover from a change of storage mode, and a process can live through one: an AutoFill
/// extension still open when the app turns encryption on, say. So every call checks the storage state first. Once
/// the vault isn't plain, or a conversion is underway, reads find nothing and writes throw
/// `VaultStoreSessionError.locked`, as a locked session does.
///
/// A write also takes `vault-slots.lock`, which a conversion holds from its journal to its commit, and checks the
/// state again once it has it. So no write can land in the plain store after a conversion has taken its snapshot,
/// where it would be lost.
public final class GuardedPlainVaultStore: Sendable {
    private let store: any CompleteVaultStore
    private let stateFile: VaultStorageStateFile
    private let encryptedFile: EncryptedVaultFile

    /// - Parameter directory: The vault's storage directory.
    public convenience init(store: PersistedLocalVaultStore, directory: URL) {
        self.init(store: store, directory: directory, fileSystem: LiveSlotFileSystem())
    }

    init(store: any CompleteVaultStore, directory: URL, fileSystem: any SlotFileSystem) {
        self.store = store
        stateFile = VaultStorageStateFile(directory: directory, fileSystem: fileSystem)
        encryptedFile = EncryptedVaultFile(directory: directory, fileSystem: fileSystem)
    }

    /// Whether the vault is in the plain store, with nothing underway. A state that can't be read counts as no.
    private var isPlain: Bool {
        (try? stateFile.read().isPlain) ?? false
    }

    /// Runs the write holding the conversion's lock, if the vault is still plain once it has it.
    private func whileStillPlain<T: Sendable>(_ write: () async throws -> T) async throws -> T {
        guard isPlain else { throw VaultStoreSessionError.locked }
        let held = try await encryptedFile.lockUntilReleased()
        defer { held.release() }
        guard isPlain else { throw VaultStoreSessionError.locked }
        return try await write()
    }
}

// MARK: - Reading

extension GuardedPlainVaultStore: VaultStoreReader {
    public func retrieve(
        query: VaultStoreQuery,
        searchPassphraseMatcher: (any SearchPassphraseMatcher)?,
    ) async throws -> VaultRetrievalResult<VaultItem> {
        guard isPlain else { return .empty() }
        return try await store.retrieve(query: query, searchPassphraseMatcher: searchPassphraseMatcher)
    }

    public var hasAnyItems: Bool {
        get async throws {
            guard isPlain else { return false }
            return try await store.hasAnyItems
        }
    }
}

extension GuardedPlainVaultStore: VaultTagStoreReader {
    public func retrieveTags() async throws -> [VaultItemTag] {
        guard isPlain else { return [] }
        return try await store.retrieveTags()
    }
}

extension GuardedPlainVaultStore: VaultStoreExporter {
    public func exportVault(userDescription: String) async throws -> VaultApplicationPayload {
        guard isPlain else { throw VaultStoreSessionError.locked }
        return try await store.exportVault(userDescription: userDescription)
    }
}

// MARK: - Writing

extension GuardedPlainVaultStore: VaultStoreWriter {
    @discardableResult
    public func insert(item: VaultItem.Write) async throws -> Identifier<VaultItem> {
        try await whileStillPlain { try await store.insert(item: item) }
    }

    public func update(id: Identifier<VaultItem>, item: VaultItem.Write) async throws {
        try await whileStillPlain { try await store.update(id: id, item: item) }
    }

    public func delete(id: Identifier<VaultItem>) async throws {
        try await whileStillPlain { try await store.delete(id: id) }
    }
}

extension GuardedPlainVaultStore: VaultStoreHOTPIncrementer {
    public func incrementCounter(id: Identifier<VaultItem>) async throws {
        try await whileStillPlain { try await store.incrementCounter(id: id) }
    }
}

extension GuardedPlainVaultStore: VaultStoreReorderable {
    public func reorder(items: Set<Identifier<VaultItem>>, to position: VaultReorderingPosition) async throws {
        try await whileStillPlain { try await store.reorder(items: items, to: position) }
    }
}

extension GuardedPlainVaultStore: VaultTagStoreWriter {
    @discardableResult
    public func insertTag(item: VaultItemTag.Write) async throws -> Identifier<VaultItemTag> {
        try await whileStillPlain { try await store.insertTag(item: item) }
    }

    public func updateTag(id: Identifier<VaultItemTag>, item: VaultItemTag.Write) async throws {
        try await whileStillPlain { try await store.updateTag(id: id, item: item) }
    }

    public func deleteTag(id: Identifier<VaultItemTag>) async throws {
        try await whileStillPlain { try await store.deleteTag(id: id) }
    }
}

extension GuardedPlainVaultStore: VaultStoreImporter {
    public func importAndMergeVault(payload: VaultApplicationPayload) async throws {
        try await whileStillPlain { try await store.importAndMergeVault(payload: payload) }
    }

    public func importAndOverrideVault(payload: VaultApplicationPayload) async throws {
        try await whileStillPlain { try await store.importAndOverrideVault(payload: payload) }
    }
}

extension GuardedPlainVaultStore: VaultStoreDeleter {
    public func deleteVault() async throws {
        try await whileStillPlain { try await store.deleteVault() }
    }
}

extension GuardedPlainVaultStore: VaultStoreKillphraseDeleter {
    /// Returns `false` once the vault isn't plain, as for a phrase that matches nothing (MANIFESTO C2).
    @discardableResult
    public func deleteItems(matchingKillphrase: String, using matcher: any KillphraseMatcher) async -> Bool {
        (try? await whileStillPlain {
            await store.deleteItems(matchingKillphrase: matchingKillphrase, using: matcher)
        }) ?? false
    }
}
