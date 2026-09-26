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
struct SlotFilePersistence: VaultRecordPersistence {
    let file: EncryptedVaultFile
    /// The vault's slot, as this vault last saved or read it.
    var slot: VaultSlotFile.OpenedSlot

    mutating func save(_ state: VaultRecordState) throws -> VaultRecordSaveOutcome {
        var payload = try EncryptedVaultPayload.encode(state)
        defer { SlotRandom.wipe(&payload.data) }
        let slot = slot
        let saved = try file.withLock { file -> (VaultSlotFile.OpenedSlot, VaultRecordSaveOutcome) in
            guard var contents = try file.read() else { throw EncryptedVaultStoreError.fileMissing }
            let sealed: VaultSlotFile.OpenedSlot
            do {
                sealed = try contents.seal(payload, in: slot)
            } catch VaultSlotFileError.slotChanged {
                let (current, saved) = try Self.reload(slot, from: contents)
                return (current, .conflict(saved: saved))
            }
            try file.write(contents) { written in
                try Self.verify(written, holds: state, in: sealed)
            }
            return (sealed, .saved)
        }
        self.slot = saved.0
        return saved.1
    }

    /// The slot and the state saved in it, after another writer saved it.
    ///
    /// - Throws: `EncryptedVaultStoreError.slotLost` if the slot doesn't open with its wrap key any more: it's been
    ///   rewrapped or replaced.
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
        return try (current, EncryptedVaultPayload.decode(contents.openPayload(of: current)))
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
            saved = try EncryptedVaultPayload.decode(written.openPayload(of: reopened))
        } catch {
            throw EncryptedVaultStoreError.verificationFailed
        }
        guard saved == state else { throw EncryptedVaultStoreError.verificationFailed }
    }
}
