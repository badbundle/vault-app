import Foundation

/// Saves an unlocked encrypted vault to its slot of the vault file.
///
/// Each save, holding the file's lock:
///
/// 1. Reads the file as it is now, and seals the new state into the slot at the next generation. Every other slot
///    is copied as it is.
/// 2. If the slot isn't at the generation this vault last saved or read, another writer has saved it since. Nothing
///    is written: the save returns what the other writer saved.
/// 3. Replaces the file (`EncryptedVaultFile.Locked.write(_:verify:)`), verifying first that the file as read back
///    opens the slot at the new generation and decodes to exactly the state being saved.
///
/// `RecordVaultStore` makes one save at a time, so a save always starts from the slot the last one left.
actor SlotFilePersistence: VaultRecordPersistence {
    /// The file, with the protection the storage mode gives it.
    private(set) var file: EncryptedVaultFile
    /// The vault's slot, as this vault last saved or read it.
    private(set) var slot: VaultSlotFile.OpenedSlot

    init(file: EncryptedVaultFile, slot: VaultSlotFile.OpenedSlot) {
        self.file = file
        self.slot = slot
    }

    func save(_ state: VaultRecordState) async throws -> VaultRecordSaveOutcome {
        var payload = try EncryptedVaultPayload.encode(state)
        defer { SlotRandom.wipe(&payload.data) }
        let slot = slot
        let (saved, outcome) = try await file.withLock { [payload] file in
            guard var contents = try file.read() else { throw EncryptedVaultStoreError.fileMissing }
            let sealed: VaultSlotFile.OpenedSlot
            do {
                sealed = try contents.seal(payload, in: slot)
            } catch VaultSlotFileError.slotChanged {
                let (current, saved) = try Self.reload(slot, from: contents)
                return (current, VaultRecordSaveOutcome.conflict(saved: saved))
            }
            try file.write(contents) { written in
                try Self.verify(written, holds: state, in: sealed)
            }
            return (sealed, .saved)
        }
        self.slot = saved
        return outcome
    }

    /// Moves the slot to another root key, with a new data key (`VaultSlotFile.rekey(_:to:payload:wrappedAt:)`),
    /// and gives the file `protection` from now on: for a password change, or turning the password off or on. The
    /// wrap time is `wrapStamper`'s, for the slot as it's saved, read under the lock.
    ///
    /// The vault sealed is what's saved: `state`, unless another writer has saved the slot since, when it's what that
    /// writer saved. `RecordVaultStore` runs this in a change's turn, so no save of its own is underway.
    ///
    /// - Returns: The state sealed, for the store to take as its own.
    /// - Throws: `EncryptedVaultStoreError.slotLost` if the slot doesn't open with its wrap key any more. The file is
    ///   unchanged when it throws.
    func rekey(
        _ state: VaultRecordState,
        to rootKey: VaultSlotRootKey,
        protection: SlotFileProtection,
        wrapStamper: any VaultWrapStamping,
    ) async throws -> VaultRecordState {
        var newFile = file
        newFile.protection = protection
        let slot = slot
        let (rekeyed, sealed) = try await newFile.withLock { file in
            guard var contents = try file.read() else { throw EncryptedVaultStoreError.fileMissing }
            let current: VaultSlotFile.OpenedSlot
            do {
                current = try contents.reopen(slot)
            } catch {
                throw EncryptedVaultStoreError.slotLost
            }
            let sealed = current.generation == slot.generation
                ? state
                : try EncryptedVaultPayload.decode(slot: current, in: contents)
            var payload = try EncryptedVaultPayload.encode(sealed)
            defer { SlotRandom.wipe(&payload.data) }
            let wrappedAt = try wrapStamper.nextWrapStamp(rewrapping: current.wrappedAt)
            let rekeyed = try contents.rekey(current, to: rootKey, payload: payload, wrappedAt: wrappedAt)
            try file.write(contents) { written in
                try Self.verify(written, holds: sealed, in: rekeyed)
                // The old key box is gone: the old root key opens nothing.
                guard (try? written.reopen(current)) == nil else { throw EncryptedVaultStoreError.verificationFailed }
            }
            return (rekeyed, sealed)
        }
        file = newFile
        self.slot = rekeyed
        return sealed
    }

    /// The slot and the state saved in it, after another writer saved it.
    ///
    /// - Throws: `EncryptedVaultStoreError.slotLost` if the slot doesn't open with its wrap key any more: it's been
    ///   rekeyed or replaced.
    private static func reload(
        _ slot: VaultSlotFile.OpenedSlot,
        from contents: VaultSlotFile,
    ) throws -> (VaultSlotFile.OpenedSlot, VaultRecordState) {
        let current: VaultSlotFile.OpenedSlot
        do {
            current = try contents.reopen(slot)
        } catch {
            throw EncryptedVaultStoreError.slotLost
        }
        return try (current, EncryptedVaultPayload.decode(slot: current, in: contents))
    }

    /// Throws `EncryptedVaultStoreError.verificationFailed` unless the file opens the slot at the sealed generation
    /// and its payload decodes to `state`.
    private static func verify(
        _ written: VaultSlotFile,
        holds state: VaultRecordState,
        in sealed: VaultSlotFile.OpenedSlot,
    ) throws {
        let saved: VaultRecordState
        do {
            let reopened = try written.reopen(sealed)
            guard reopened.generation == sealed.generation else {
                throw EncryptedVaultStoreError.verificationFailed
            }
            saved = try EncryptedVaultPayload.decode(slot: reopened, in: written)
        } catch {
            throw EncryptedVaultStoreError.verificationFailed
        }
        guard saved == state else { throw EncryptedVaultStoreError.verificationFailed }
    }
}
