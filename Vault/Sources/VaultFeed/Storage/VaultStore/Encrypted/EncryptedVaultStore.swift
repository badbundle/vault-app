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
///   other writer saved and makes the change again on top of it, so each writer's change is applied once. An update
///   to an item the other writer changed too replaces it, as the later save does in the SQLite store, but keeps a
///   HOTP counter it advanced. Only if conflicts keep happening does the change fail, with
///   `EncryptedVaultStoreError.conflict`.
/// - Deleting by killphrase returns `false` whatever the failure, the same as when nothing matches (MANIFESTO C2).
///
/// It behaves exactly as `RecordVaultStore` does, which it's built on. Finding the slot a password opens, within the
/// unlock deadline, is `VaultUnlockService`'s job. See "Reading and writing while unlocked" in
/// `docs/on-device-encryption.md`.
///
/// In an app extension, every call first checks the vault is still stored the way it was when it opened
/// (`VaultAccessGuard`): once it isn't, reads find nothing and writes throw `VaultStoreSessionError.locked`.
public final class EncryptedVaultStore: Sendable {
    let records: RecordVaultStore
    /// Where the vault is saved: its slot of the file.
    let persistence: SlotFilePersistence
    /// Derives a new password's key and tries it on a slot, as unlocking does.
    private let work: any VaultUnlockWork
    /// Stamps the key wrap of a duress vault made from this one, and of this vault when it's rekeyed.
    private let wrapStamper: any VaultWrapStamping
    /// Checked on every call, in an app extension. `nil` in the app.
    private let accessGuard: VaultAccessGuard?

    /// The vault in `slot`, whose payload has already been read.
    ///
    /// - Parameters:
    ///   - file: Where the vault file is.
    ///   - slot: The vault's slot, as it was opened.
    ///   - state: The vault the slot's payload holds.
    ///   - work: What derives a password's key and tries it on a slot, when making a duress vault: the unlock
    ///     service's, so both derive the same way.
    ///   - wrapStamper: What stamps the key wrap of a duress vault made from this one, and of this vault when it's
    ///     rekeyed.
    ///   - memoryCheck: Checked before every save, in the AutoFill extension.
    ///   - accessGuard: Checked on every call, and again under the file's lock before every save, in an app
    ///     extension.
    init(
        file: EncryptedVaultFile,
        slot: VaultSlotFile.OpenedSlot,
        state: VaultRecordState,
        sortOrder: VaultStoreSortOrder = .relativeOrder,
        currentDate: @escaping @Sendable () -> Date = { Date() },
        work: any VaultUnlockWork = LiveVaultUnlockWork(),
        wrapStamper: any VaultWrapStamping = VaultDeviceWrapStamper(),
        memoryCheck: VaultWriteMemoryCheck? = nil,
        accessGuard: VaultAccessGuard? = nil,
    ) {
        let persistence = SlotFilePersistence(
            file: file,
            slot: slot,
            memoryCheck: memoryCheck,
            accessGuard: accessGuard,
        )
        self.persistence = persistence
        records = RecordVaultStore(
            state: state,
            sortOrder: sortOrder,
            currentDate: currentDate,
            persistence: persistence,
        )
        self.work = work
        self.wrapStamper = wrapStamper
        self.accessGuard = accessGuard
    }

    /// Whether the vault may still be read: always in the app.
    private var isReadable: Bool {
        accessGuard?.isStillOpen ?? true
    }

    /// - Throws: `VaultStoreSessionError.locked` if the vault may not be written now.
    private func checkWrite() throws {
        try accessGuard?.checkWrite()
    }

    /// The slot the vault is in.
    var slotIndex: Int {
        get async {
            await persistence.slot.index
        }
    }

    /// Moves the vault to another root key, with a new data key, and gives the file `protection` from now on: for
    /// a password change, or turning the password off or on. Only this vault's slot changes. Its wrap time is
    /// stamped by `VaultWrapStamping`, later than every wrap this device has made and than its own.
    ///
    /// It waits for any change underway to be saved first, and nothing is changed while it runs.
    func rekey(to rootKey: VaultSlotRootKey, protection: SlotFileProtection) async throws {
        try await records.whileChanging { [persistence, wrapStamper] state in
            try await persistence.rekey(state, to: rootKey, protection: protection, wrapStamper: wrapStamper)
        }
    }

    /// Reads the vault in `slot`.
    ///
    /// - Parameters:
    ///   - file: Where the vault file is.
    ///   - contents: The file, as `file.open()` read it.
    ///   - slot: The vault's slot, opened in `contents`.
    /// - Throws: If the slot's payload doesn't open or decode, including
    ///   `EncryptedVaultStoreError.unsupportedPayloadVersion(_:)` for a vault saved by a newer version of the app.
    convenience init(
        file: EncryptedVaultFile,
        contents: VaultSlotFile,
        slot: VaultSlotFile.OpenedSlot,
        sortOrder: VaultStoreSortOrder = .relativeOrder,
        currentDate: @escaping @Sendable () -> Date = { Date() },
        work: any VaultUnlockWork = LiveVaultUnlockWork(),
        wrapStamper: any VaultWrapStamping = VaultDeviceWrapStamper(),
    ) throws {
        try self.init(
            file: file,
            slot: slot,
            state: EncryptedVaultPayload.decode(slot: slot, in: contents),
            sortOrder: sortOrder,
            currentDate: currentDate,
            work: work,
            wrapStamper: wrapStamper,
        )
    }
}

// MARK: - Reading

extension EncryptedVaultStore: VaultStoreReader {
    public func retrieve(
        query: VaultStoreQuery,
        searchPassphraseMatcher: (any SearchPassphraseMatcher)?,
    ) async throws -> VaultRetrievalResult<VaultItem> {
        guard isReadable else { return .empty() }
        return try await records.retrieve(query: query, searchPassphraseMatcher: searchPassphraseMatcher)
    }

    public var hasAnyItems: Bool {
        get async {
            guard isReadable else { return false }
            return await records.hasAnyItems
        }
    }
}

extension EncryptedVaultStore: VaultTagStoreReader {
    public func retrieveTags() async throws -> [VaultItemTag] {
        guard isReadable else { return [] }
        return try await records.retrieveTags()
    }
}

extension EncryptedVaultStore: VaultStoreExporter {
    public func exportVault(userDescription: String) async throws -> VaultApplicationPayload {
        guard isReadable else { throw VaultStoreSessionError.locked }
        return try await records.exportVault(userDescription: userDescription)
    }
}

// MARK: - Writing

extension EncryptedVaultStore: VaultStoreWriter {
    @discardableResult
    public func insert(item: VaultItem.Write) async throws -> Identifier<VaultItem> {
        try checkWrite()
        return try await records.insert(item: item)
    }

    public func update(id: Identifier<VaultItem>, item: VaultItem.Write) async throws {
        try checkWrite()
        try await records.update(id: id, item: item)
    }

    public func delete(id: Identifier<VaultItem>) async throws {
        try checkWrite()
        try await records.delete(id: id)
    }
}

extension EncryptedVaultStore: VaultStoreHOTPIncrementer {
    public func incrementCounter(id: Identifier<VaultItem>) async throws {
        try checkWrite()
        try await records.incrementCounter(id: id)
    }
}

extension EncryptedVaultStore: VaultStoreReorderable {
    public func reorder(items: Set<Identifier<VaultItem>>, to position: VaultReorderingPosition) async throws {
        try checkWrite()
        try await records.reorder(items: items, to: position)
    }
}

extension EncryptedVaultStore: VaultTagStoreWriter {
    @discardableResult
    public func insertTag(item: VaultItemTag.Write) async throws -> Identifier<VaultItemTag> {
        try checkWrite()
        return try await records.insertTag(item: item)
    }

    public func updateTag(id: Identifier<VaultItemTag>, item: VaultItemTag.Write) async throws {
        try checkWrite()
        try await records.updateTag(id: id, item: item)
    }

    public func deleteTag(id: Identifier<VaultItemTag>) async throws {
        try checkWrite()
        try await records.deleteTag(id: id)
    }
}

extension EncryptedVaultStore: VaultStoreImporter {
    public func importAndMergeVault(payload: VaultApplicationPayload) async throws {
        try checkWrite()
        try await records.importAndMergeVault(payload: payload)
    }

    public func importAndOverrideVault(payload: VaultApplicationPayload) async throws {
        try checkWrite()
        try await records.importAndOverrideVault(payload: payload)
    }
}

extension EncryptedVaultStore: VaultStoreDeleter {
    /// Empties this vault. Its slot, and its password, stay.
    public func deleteVault() async throws {
        try checkWrite()
        try await records.deleteVault()
    }
}

extension EncryptedVaultStore: VaultStoreKillphraseDeleter {
    @discardableResult
    public func deleteItems(matchingKillphrase: String, using matcher: any KillphraseMatcher) async -> Bool {
        // As for a phrase that matches nothing (MANIFESTO C2).
        guard (try? checkWrite()) != nil else { return false }
        return await records.deleteItems(matchingKillphrase: matchingKillphrase, using: matcher)
    }
}

// MARK: - Duress vault

extension EncryptedVaultStore {
    /// Makes a duress vault from this vault: a new, empty vault that `password` opens at the next unlock (VAULT-23).
    ///
    /// It goes in the first of this vault's duress slots, so making another replaces the one before, and it gets this
    /// vault's other duress slots, plus one chosen at random (`VaultDuressSlots`). The file is replaced as for a save,
    /// under its lock and verified. This vault's own slot isn't written, so it keeps working with its password.
    ///
    /// The real vault and a duress vault make one the same way, with the same steps, and the new vault's payload has
    /// the same shape as every other's. Nothing in either vault records that the duress vault was made.
    ///
    /// - A password that's this vault's own App Lock Password is refused. One that happens to open another slot is
    ///   accepted, without anything being tried against the other slots: refusing it would be an oracle. If a
    ///   password opens more than one slot, unlocking opens the most recently wrapped, which is this new vault: its
    ///   wrap is stamped by `VaultWrapStamping`, later than every wrap this device has made and than this vault's
    ///   own, whatever the device's clock says.
    /// - It derives the password's key as unlocking does, which takes about half a second.
    ///
    /// Never log, print or measure anything about it (MANIFESTO C3).
    ///
    /// - Throws: `VaultDuressVaultError.matchesAppLockPassword` for this vault's own password, `.unavailable` if this
    ///   vault's duress slots aren't a valid list, or an error reading or replacing the file. The file is unchanged
    ///   when it throws.
    public func makeDuressVault(password: String) async throws {
        try checkWrite()
        let slot = await persistence.slot
        let placement = try await VaultDuressSlots.placement(
            madeFromSlot: slot.index,
            duressSlots: records.state.vault.duressSlots,
        )
        try await persistence.makeDuressVault(
            password: password,
            placement: placement,
            wrapStamper: wrapStamper,
            work: work,
        )
    }
}

// MARK: - Backup settings

extension EncryptedVaultStore {
    /// This vault's own backup settings, as saved in its payload.
    public var backupSettings: VaultBackupSettings {
        get async {
            await records.state.vault.settings
        }
    }

    /// Changes this vault's backup settings, and saves them to its slot like any other change: if another writer
    /// saved first, the change is made again on top of what it saved.
    ///
    /// Use `VaultStoreSession.whileOpen(_:_:)` around it, so it's only made while this vault is the open one.
    func updateBackupSettings(_ update: @escaping @Sendable (inout VaultBackupSettings) -> Void) async throws {
        try checkWrite()
        try await records.change { state in
            update(&state.vault.settings)
        }
    }
}
