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
    let file: EncryptedVaultFile
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

// MARK: - Duress vault

extension SlotFilePersistence {
    /// Makes a duress vault, for `password`, where `placement` says, from this vault (VAULT-23).
    ///
    /// Derives the password's key as unlocking does, then, holding the file's lock:
    ///
    /// 1. Refuses the password if it opens this vault's own slot: it's this vault's App Lock Password. That's the one
    ///    slot it tries. Refusing a password that opens any other slot would tell whoever holds this vault's password
    ///    that another vault exists, and would let them test guesses at it here, without the unlock delay.
    /// 2. Creates the new vault, empty, in `placement.slot`, with a new data key wrapped by the password's key at a
    ///    time `wrapStamper` gives it after this vault's own wrap time, and the duress slots `placement` gives it.
    ///    Whatever was in that slot is gone.
    /// 3. Replaces the file as a save does, verifying first that it opens the new vault and that this vault's slot is
    ///    as it was.
    ///
    /// This vault's slot isn't written, so it keeps working with its password, and the file shows no change in it.
    /// The steps are the same whichever vault this is.
    func makeDuressVault(
        password: String,
        placement: VaultDuressSlots.Placement,
        wrapStamper: any VaultWrapStamping,
        work: any VaultUnlockWork,
    ) async throws {
        guard let (header, _) = try file.readHeader() else { throw EncryptedVaultStoreError.fileMissing }
        // The derivation unlocking uses, off the actor: about half a second on the device that created the file.
        let key = try await Task.detached(priority: .userInitiated) {
            try work.passwordKey(for: password, header: header)
        }.value
        let state = VaultRecordState(
            items: [],
            tags: [],
            vault: VaultMetadata(duressSlots: placement.duressSlots),
        )
        var payload = try EncryptedVaultPayload.encode(state)
        defer { SlotRandom.wipe(&payload.data) }
        let slot = slot
        try await file.withLock { [payload] file in
            guard var contents = try file.read() else { throw EncryptedVaultStoreError.fileMissing }
            let current: VaultSlotFile.OpenedSlot
            do {
                current = try contents.reopen(slot)
            } catch {
                throw EncryptedVaultStoreError.slotLost
            }
            guard work.openKeyBox(current.index, in: contents, with: key) == nil else {
                throw VaultDuressVaultError.matchesAppLockPassword
            }
            // Later than every wrap this device has made, and than this vault's own, whatever the clock says:
            // otherwise setting the clock back would make the new vault older than one a shared password also opens.
            let wrappedAt = try wrapStamper.nextWrapStamp(rewrapping: current.wrappedAt)
            let created = try contents.createVault(
                inSlot: placement.slot,
                rootKey: key,
                payload: payload,
                wrappedAt: wrappedAt,
            )
            try file.write(contents) { written in
                try Self.verify(written, holds: state, in: created)
                guard (try? written.reopen(current))?.generation == current.generation else {
                    throw EncryptedVaultStoreError.verificationFailed
                }
            }
        }
    }
}
