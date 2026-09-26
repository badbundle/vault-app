import Foundation

/// Turns encryption on, when the App Lock Password is first set: converts the plain SQLite store into an encrypted
/// vault, and switches the store session to it.
///
/// **Preconditions**, checked before anything changes or is derived:
///
/// - Encryption isn't on already, and no conversion is underway.
/// - The plain store opened normally, so it holds the whole vault.
/// - No phrases are waiting to be rehashed after a schema migration: they're plaintext, and would outlive the
///   conversion.
/// - Any archives of the plain store, set aside when it failed to open, are plaintext copies of the vault too. The
///   user has to agree to delete them.
/// - The vault fits the largest slot (`VaultEncryptionError.vaultTooLarge`).
///
/// **Steps.** Each is journaled in `vault-storage-state.json`, so launch recovery (`VaultStorageRecovery`) can finish
/// or undo a conversion the app was stopped in the middle of:
///
/// 1. Resets the attempt counter, so a count left from before doesn't carry over to the new password.
/// 2. Takes `vault-slots.lock` and holds it until the commit. Journals `encrypting`, so the extensions stay away from
///    the plain store, and locks the store session, so the app's own writes finish first. An extension's write to
///    the plain store takes the lock too, and checks the journal once it has it (`GuardedPlainVaultStore`).
/// 3. Takes a snapshot of the plain store as records, field for field, including items that don't decode.
/// 4. Calibrates the key derivation for this device, derives the password's key with a fresh salt, and builds the
///    file: the vault in a slot chosen at random, with ten duress slots, and every other slot random.
/// 5. Writes it through a flushed temp file and verifies it before the rename: the whole unlock path with the
///    password has to open exactly that slot and nothing else, and decode to exactly the snapshot.
/// 6. Commits: journals the password mode, the device's unlock deadline, and the plain store's deletion. The
///    journal's rename is the commit point.
/// 7. Lets go of the plain store, and deletes its files, its pending rehash files and the confirmed archives.
/// 8. Clears the QuickType identity store and reloads the widgets, journaled so the next launch does it again if
///    the app stops first. Then it clears the journal, and switches the store session to the vault, unless the app
///    has locked meanwhile.
///
/// A failure before the commit undoes the conversion, once the journal on disk shows it didn't commit, and goes back
/// to the plain store. Nothing deletes the plain store before the encrypted vault is committed. See "Migration: plain
/// to encrypted" in `docs/on-device-encryption.md`.
public actor VaultEncryptionConverter {
    /// How many duress slots each vault is given (L in the design).
    static let duressSlotCount = 10

    /// What the app does around a conversion, outside storage.
    public struct Hooks: Sendable {
        /// Lets go of the plain store once the conversion has committed, so its database closes before its files
        /// are deleted. The store session has already switched away from it.
        public var releasePlainStore: @Sendable () async -> Void
        /// Empties the QuickType identity store, which holds every visible code's issuer and account name.
        public var clearCredentialIdentities: @Sendable () async -> Void
        /// Reloads the widgets' timelines, so none keeps showing a code.
        public var reloadWidgets: @Sendable () async -> Void

        public init(
            releasePlainStore: @escaping @Sendable () async -> Void,
            clearCredentialIdentities: @escaping @Sendable () async -> Void,
            reloadWidgets: @escaping @Sendable () async -> Void,
        ) {
            self.releasePlainStore = releasePlainStore
            self.clearCredentialIdentities = clearCredentialIdentities
            self.reloadWidgets = reloadWidgets
        }
    }

    private let directory: URL
    private let fileSystem: any SlotFileSystem
    /// The plain store, until the conversion commits.
    private var plainStore: PersistedLocalVaultStore?
    /// Whether a conversion is underway: a second one is refused before it does anything.
    private var isConverting = false
    private let plainStoreOpenedNormally: Bool
    private let session: VaultStoreSession
    private let archives: any VaultStoreArchiving
    private let attemptCounter: AppLockPasswordAttemptCounter
    private let hooks: Hooks
    private let calibrate: @Sendable () throws -> AppLockKeyDerivationCalibration

    /// - Parameters:
    ///   - directory: The vault's storage directory, where the plain store is and the encrypted file will be.
    ///   - plainStore: The plain store, which `session` reads and writes now.
    ///   - plainStoreOpenedNormally: Whether the plain store opened without being set aside, rather than as an
    ///     empty fallback.
    ///   - archives: The archives of the plain store, set aside when it failed to open.
    public init(
        directory: URL,
        plainStore: PersistedLocalVaultStore,
        plainStoreOpenedNormally: Bool,
        session: VaultStoreSession,
        archives: any VaultStoreArchiving,
        attemptCounter: AppLockPasswordAttemptCounter,
        hooks: Hooks,
    ) {
        self.init(
            directory: directory,
            fileSystem: LiveSlotFileSystem(),
            plainStore: plainStore,
            plainStoreOpenedNormally: plainStoreOpenedNormally,
            session: session,
            archives: archives,
            attemptCounter: attemptCounter,
            hooks: hooks,
            calibrate: { try AppLockKeyDerivationCalibrator().calibrate() },
        )
    }

    init(
        directory: URL,
        fileSystem: any SlotFileSystem,
        plainStore: PersistedLocalVaultStore,
        plainStoreOpenedNormally: Bool,
        session: VaultStoreSession,
        archives: any VaultStoreArchiving,
        attemptCounter: AppLockPasswordAttemptCounter,
        hooks: Hooks,
        calibrate: @escaping @Sendable () throws -> AppLockKeyDerivationCalibration,
    ) {
        self.directory = directory
        self.fileSystem = fileSystem
        self.plainStore = plainStore
        self.plainStoreOpenedNormally = plainStoreOpenedNormally
        self.session = session
        self.archives = archives
        self.attemptCounter = attemptCounter
        self.hooks = hooks
        self.calibrate = calibrate
    }
}

/// Why encryption couldn't be turned on. Each leaves the plain store as it was.
public enum VaultEncryptionError: Error, Equatable, Sendable {
    /// Encryption is on already, or a conversion is underway.
    case alreadyEncrypted
    /// The plain store didn't open normally, so it might not hold the whole vault.
    case plainStoreDidNotOpen
    /// Phrases from an older version of the app are still waiting to be rehashed, in plaintext, and would outlive
    /// the conversion.
    case pendingRehashes
    /// There are archives of the plain store, which are plaintext copies of the vault, and the user hasn't agreed
    /// to delete them.
    case archivesNeedDeleting
    /// The vault is too large for the largest slot of the encrypted file.
    case vaultTooLarge
}

// MARK: - Converting

extension VaultEncryptionConverter {
    /// Converts the plain store into an encrypted vault that `password` opens, and switches the store session to
    /// it.
    ///
    /// It takes a couple of seconds: calibrating, then deriving the key twice, once to write and once to verify.
    ///
    /// - Parameters:
    ///   - password: The new App Lock Password.
    ///   - deletingArchives: Whether the user has agreed to delete the plain store's archives, if there are any.
    /// - Throws: `VaultEncryptionError` if a precondition isn't met, or whatever stopped the conversion. The plain
    ///   store is then still the vault, and the session reads and writes it again, unless the journal on disk can't
    ///   be read to confirm the conversion didn't commit: then the session stays locked, and the next launch decides.
    public func encrypt(password: String, deletingArchives: Bool) async throws {
        // Checked before the first suspension, so two conversions can't overlap.
        guard !isConverting, let plainStore else { throw VaultEncryptionError.alreadyEncrypted }
        isConverting = true
        defer { isConverting = false }

        let stateFile = VaultStorageStateFile(directory: directory, fileSystem: fileSystem)
        guard try stateFile.read() == .plain else { throw VaultEncryptionError.alreadyEncrypted }
        guard plainStoreOpenedNormally else { throw VaultEncryptionError.plainStoreDidNotOpen }
        guard try pendingRehashesAreEmpty() else { throw VaultEncryptionError.pendingRehashes }
        let archiveNames = archives.archives().map(\.url.lastPathComponent)
        guard archiveNames.isEmpty || deletingArchives else { throw VaultEncryptionError.archivesNeedDeleting }
        guard try await Self.fitsTheLargestSlot(plainStore.recordState()) else {
            throw VaultEncryptionError.vaultTooLarge
        }
        try await attemptCounter.reset()

        // Held from the journal to the commit. An extension's write to the plain store takes it too, and checks the
        // mode once it has it, so none can land in the plain store after the snapshot (`GuardedPlainVaultStore`).
        let file = EncryptedVaultFile(directory: directory, fileSystem: fileSystem)
        let held = try await file.lockUntilReleased()
        var wroteEncryptedFile = false
        let converted: Converted
        let lockEpoch: Int
        do {
            try stateFile.write(VaultStorageState(mode: .plain, transition: .encrypting))
            await session.lock()
            lockEpoch = await session.lockEpoch
            converted = try await convert(plainStore, password: password)
            guard try held.locked.read() == nil else { throw VaultEncryptionError.alreadyEncrypted }
            try held.locked.write(converted.file) { written in
                try Self.verify(written, opens: converted.state, inSlot: converted.slot.index, password: password)
            }
            wroteEncryptedFile = true
            // The commit: once this rename is done, the encrypted vault is the vault.
            try stateFile.write(VaultStorageState(
                mode: .password,
                transition: .deletingPlainStore(archives: archiveNames),
                unlockDeadline: converted.unlockDeadline,
            ))
        } catch {
            await undo(
                stateFile: stateFile,
                held: held,
                wroteEncryptedFile: wroteEncryptedFile,
                plainStore: plainStore,
            )
            held.release()
            throw error
        }
        held.release()

        self.plainStore = nil
        await hooks.releasePlainStore()
        var deletedPlainStore = false
        do {
            try VaultStorageRecovery(directory: directory, fileSystem: fileSystem)
                .deletePlainStore(archives: archiveNames)
            try stateFile.write(VaultStorageState(
                mode: .password,
                transition: .clearingSystemSurfaces,
                unlockDeadline: converted.unlockDeadline,
            ))
            deletedPlainStore = true
        } catch {
            // The journal still says to delete the plain store, so the next launch finishes it, then clears the
            // system surfaces again.
        }
        await hooks.clearCredentialIdentities()
        await hooks.reloadWidgets()
        if deletedPlainStore {
            // If this fails, the next launch clears the surfaces again, which does no harm.
            try? stateFile.write(VaultStorageState(mode: .password, unlockDeadline: converted.unlockDeadline))
        }
        // If the app locked while converting, it stays locked: the vault opens with the password.
        let store = EncryptedVaultStore(file: file, slot: converted.slot, state: converted.state)
        _ = await session.switchTo(.unlocked(store), unlessLockedSince: lockEpoch)
    }

    private struct Converted: Sendable {
        var file: VaultSlotFile
        var slot: VaultSlotFile.OpenedSlot
        var state: VaultRecordState
        var unlockDeadline: Duration
    }

    /// Takes the snapshot and builds the encrypted file in memory.
    private func convert(_ plainStore: PersistedLocalVaultStore, password: String) async throws -> Converted {
        let realSlot = Int.random(in: VaultSlotFile.slotIndices)
        var state = try await plainStore.recordState()
        state.vault.duressSlots = Array(
            VaultSlotFile.slotIndices.filter { $0 != realSlot }.shuffled().prefix(Self.duressSlotCount),
        )
        // Checked again: the vault could have grown since the precondition was checked.
        guard try Self.fitsTheLargestSlot(state) else { throw VaultEncryptionError.vaultTooLarge }
        var payload = try EncryptedVaultPayload.encode(state)
        defer { SlotRandom.wipe(&payload.data) }

        let calibrate = calibrate
        let (calibration, file, slot) = try await Task.detached(priority: .userInitiated) { [payload] in
            let calibration = try calibrate()
            var file = try VaultSlotFile(kdfParameters: calibration.parameters)
            let key = try file.header.passwordKey(for: password)
            let slot = try file.createVault(inSlot: realSlot, rootKey: key, payload: payload, wrappedAt: Date())
            return (calibration, file, slot)
        }.value
        return Converted(file: file, slot: slot, state: state, unlockDeadline: calibration.unlockDeadline)
    }

    /// Goes back to the plain store after a conversion that didn't commit.
    ///
    /// It only goes back once the journal on disk shows the conversion didn't commit, and only deletes the encrypted
    /// file if this conversion wrote it. If the journal can't be read, the session stays locked, and the next
    /// launch's recovery decides from what's on disk. If deleting the file or the journal fails, the journal still
    /// says `encrypting`, which recovery undoes the same way, keeping the plain store.
    private func undo(
        stateFile: VaultStorageStateFile,
        held: EncryptedVaultFile.HeldLock,
        wroteEncryptedFile: Bool,
        plainStore: PersistedLocalVaultStore,
    ) async {
        guard let onDisk = try? stateFile.read(), onDisk.mode == .plain else { return }
        let removed = wroteEncryptedFile ? (try? held.locked.removeFile()) != nil : true
        if removed {
            try? stateFile.write(.plain)
        }
        await session.switchTo(.plain(plainStore))
    }

    private func pendingRehashesAreEmpty() throws -> Bool {
        let killphrases = PendingKillphraseRehashStore(
            fileURL: PendingKillphraseRehashStore.defaultURL(storeDirectory: directory),
        )
        let searchPassphrases = PendingSearchPassphraseRehashStore(
            fileURL: PendingSearchPassphraseRehashStore.defaultURL(storeDirectory: directory),
        )
        return try killphrases.read().isEmpty && searchPassphrases.read().isEmpty
    }

    /// Whether the vault fits the largest slot, once encoded and compressed as a save would.
    private static func fitsTheLargestSlot(_ state: VaultRecordState) throws -> Bool {
        var payload = try EncryptedVaultPayload.encode(state)
        defer { SlotRandom.wipe(&payload.data) }
        guard payload.data.count <= VaultSlotFile.maximumPayloadLength else { return false }
        var compressed = try VaultSlotCompression.lzfse.compress(payload.data)
        defer { SlotRandom.wipe(&compressed) }
        return compressed.count <= VaultSlotFile.payloadCapacity(slotSize: VaultSlotFile.maximumSlotSize)
    }

    /// Unlocks the written file as `VaultUnlockService` does, deriving the key again from the password and the
    /// file's header, and requires it to open that one slot and decode to exactly the snapshot.
    private static func verify(
        _ written: VaultSlotFile,
        opens state: VaultRecordState,
        inSlot index: Int,
        password: String,
    ) throws {
        let work = LiveVaultUnlockWork()
        let key = try work.passwordKey(for: password, header: written.header)
        let opened = VaultSlotFile.slotIndices.compactMap { work.openKeyBox($0, in: written, with: key) }
        guard opened.map(\.index) == [index], try work.openBody(of: opened[0], in: written) == state else {
            throw EncryptedVaultStoreError.verificationFailed
        }
    }
}
