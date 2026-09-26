import Foundation
import FoundationExtensions
import VaultCore

/// An unlocked encrypted vault: its records in memory, saved to its slot of the encrypted vault file on every change.
///
/// Reads, searches and killphrase matching all happen in memory. Every change works out the new records first, then
/// saves them by replacing the whole file, verified, under the file's lock (`SlotFilePersistence`,
/// `EncryptedVaultFile`), and only then publishes them. So memory is never ahead of the disk, and a change that
/// fails leaves both as they were and throws.
///
/// - If another app or extension saved the vault since this store last read or saved it, the store takes what the
///   other writer saved and makes the change again on top of it, so neither writer's change is lost. Only if that
///   keeps happening does the change fail, with `EncryptedVaultStoreError.conflict`.
/// - Deleting by killphrase returns `false` whatever the failure, the same as when nothing matches (MANIFESTO C2).
///
/// It behaves exactly as `RecordVaultStore` does, which it's built on. Finding the slot a password opens, within the
/// unlock deadline, is the unlock service's job. See "Reading and writing while unlocked" in
/// `docs/on-device-encryption.md`.
public final class EncryptedVaultStore: Sendable {
    let records: RecordVaultStore

    /// Reads the vault in `slot`.
    ///
    /// - Parameters:
    ///   - file: Where the vault file is.
    ///   - contents: The file, as `file.open()` read it.
    ///   - slot: The vault's slot, opened in `contents`.
    /// - Throws: If the slot's payload doesn't open or decode, including
    ///   `EncryptedVaultStoreError.unsupportedPayloadVersion(_:)` for a vault saved by a newer version of the app.
    init(
        file: EncryptedVaultFile,
        contents: VaultSlotFile,
        slot: VaultSlotFile.OpenedSlot,
        sortOrder: VaultStoreSortOrder = .relativeOrder,
        currentDate: @escaping @Sendable () -> Date = { Date() },
    ) throws {
        let state = try EncryptedVaultPayload.decode(slot: slot, in: contents)
        records = RecordVaultStore(
            state: state,
            sortOrder: sortOrder,
            currentDate: currentDate,
            persistence: SlotFilePersistence(file: file, slot: slot),
        )
    }
}

// MARK: - Reading

extension EncryptedVaultStore: VaultStoreReader {
    public func retrieve(
        query: VaultStoreQuery,
        searchPassphraseMatcher: (any SearchPassphraseMatcher)?,
    ) async throws -> VaultRetrievalResult<VaultItem> {
        try await records.retrieve(query: query, searchPassphraseMatcher: searchPassphraseMatcher)
    }

    public var hasAnyItems: Bool {
        get async {
            await records.hasAnyItems
        }
    }
}

extension EncryptedVaultStore: VaultTagStoreReader {
    public func retrieveTags() async throws -> [VaultItemTag] {
        try await records.retrieveTags()
    }
}

extension EncryptedVaultStore: VaultStoreExporter {
    public func exportVault(userDescription: String) async throws -> VaultApplicationPayload {
        try await records.exportVault(userDescription: userDescription)
    }
}

// MARK: - Writing

extension EncryptedVaultStore: VaultStoreWriter {
    @discardableResult
    public func insert(item: VaultItem.Write) async throws -> Identifier<VaultItem> {
        try await records.insert(item: item)
    }

    public func update(id: Identifier<VaultItem>, item: VaultItem.Write) async throws {
        try await records.update(id: id, item: item)
    }

    public func delete(id: Identifier<VaultItem>) async throws {
        try await records.delete(id: id)
    }
}

extension EncryptedVaultStore: VaultStoreHOTPIncrementer {
    public func incrementCounter(id: Identifier<VaultItem>) async throws {
        try await records.incrementCounter(id: id)
    }
}

extension EncryptedVaultStore: VaultStoreReorderable {
    public func reorder(items: Set<Identifier<VaultItem>>, to position: VaultReorderingPosition) async throws {
        try await records.reorder(items: items, to: position)
    }
}

extension EncryptedVaultStore: VaultTagStoreWriter {
    @discardableResult
    public func insertTag(item: VaultItemTag.Write) async throws -> Identifier<VaultItemTag> {
        try await records.insertTag(item: item)
    }

    public func updateTag(id: Identifier<VaultItemTag>, item: VaultItemTag.Write) async throws {
        try await records.updateTag(id: id, item: item)
    }

    public func deleteTag(id: Identifier<VaultItemTag>) async throws {
        try await records.deleteTag(id: id)
    }
}

extension EncryptedVaultStore: VaultStoreImporter {
    public func importAndMergeVault(payload: VaultApplicationPayload) async throws {
        try await records.importAndMergeVault(payload: payload)
    }

    public func importAndOverrideVault(payload: VaultApplicationPayload) async throws {
        try await records.importAndOverrideVault(payload: payload)
    }
}

extension EncryptedVaultStore: VaultStoreDeleter {
    /// Empties this vault. Its slot, and its password, stay.
    public func deleteVault() async throws {
        try await records.deleteVault()
    }
}

extension EncryptedVaultStore: VaultStoreKillphraseDeleter {
    @discardableResult
    public func deleteItems(matchingKillphrase: String, using matcher: any KillphraseMatcher) async -> Bool {
        await records.deleteItems(matchingKillphrase: matchingKillphrase, using: matcher)
    }
}
