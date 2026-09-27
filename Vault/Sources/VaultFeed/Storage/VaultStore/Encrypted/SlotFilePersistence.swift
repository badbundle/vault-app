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
/// Deleting all data saves the same way, and fills every other slot with random bytes in the same write
/// (`saveDestroyingOtherVaults(_:)`), so every other vault goes with it or none does.
///
/// `RecordVaultStore` makes one save at a time, so a save always starts from the slot the last one left.
actor SlotFilePersistence: VaultRecordPersistence {
    /// The file, with the protection the storage mode gives it.
    private(set) var file: EncryptedVaultFile
    /// The vault's slot, as this vault last saved or read it.
    private(set) var slot: VaultSlotFile.OpenedSlot
    /// Checked before each save in the AutoFill extension. `nil` in the app.
    private let memoryCheck: VaultWriteMemoryCheck?
    /// Checked holding the file's lock before each save, in an app extension. `nil` in the app.
    private let accessGuard: VaultAccessGuard?

    init(
        file: EncryptedVaultFile,
        slot: VaultSlotFile.OpenedSlot,
        memoryCheck: VaultWriteMemoryCheck? = nil,
        accessGuard: VaultAccessGuard? = nil,
    ) {
        self.file = file
        self.slot = slot
        self.memoryCheck = memoryCheck
        self.accessGuard = accessGuard
    }

    func save(_ state: VaultRecordState) async throws -> VaultRecordSaveOutcome {
        try await save(state, destroyingOtherVaults: false)
    }

    /// Saves `state`, and fills every other slot with fresh random bytes in the same write (VAULT-74): the real vault
    /// and any duress vaults are gone, whichever vault this is. Slots that held nothing change the same way, so the
    /// file doesn't show whether any did.
    func saveDestroyingOtherVaults(_ state: VaultRecordState) async throws -> VaultRecordSaveOutcome {
        try await save(state, destroyingOtherVaults: true)
    }

    private func save(_ state: VaultRecordState, destroyingOtherVaults: Bool) async throws -> VaultRecordSaveOutcome {
        var payload = try EncryptedVaultPayload.encode(state)
        defer { SlotRandom.wipe(&payload.data) }
        if let memoryCheck {
            // Before the file is read: from here on the save holds it twice, and the JSON four times over.
            guard let (_, fileSize) = try file.readHeader() else { throw EncryptedVaultStoreError.fileMissing }
            guard memoryCheck.allowsSave(fileSize: fileSize, jsonSize: payload.data.count) else {
                throw EncryptedVaultStoreError.notEnoughMemory
            }
        }
        let slot = slot
        let (saved, outcome) = try await file.withLock { [payload, accessGuard] file in
            // A rekey or an erase holds the lock while it changes the vault, and changes the storage state first.
            try accessGuard?.checkWrite()
            guard var contents = try file.read() else { throw EncryptedVaultStoreError.fileMissing }
            let sealed: VaultSlotFile.OpenedSlot
            do {
                sealed = try contents.seal(payload, in: slot)
            } catch VaultSlotFileError.slotChanged {
                let (current, saved) = try Self.reload(slot, from: contents)
                return (current, VaultRecordSaveOutcome.conflict(saved: saved))
            }
            if destroyingOtherVaults {
                contents.randomizeSlots(except: sealed)
            }
            // The file is read back and checked byte for byte first, so every other slot is as written here.
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
