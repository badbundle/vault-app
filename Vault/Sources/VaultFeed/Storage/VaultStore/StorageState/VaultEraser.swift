import Foundation
import VaultCore

/// Erases every vault on the device by destroying their keys, and leaves a fresh, empty plain store: what happens
/// after too many wrong App Lock Passwords in a row, when the user has turned that on (VAULT-34).
///
/// Every vault's data key is wrapped in `vault-slots.v1`, so removing that file makes every vault unreadable at once.
/// The erase doesn't look at which vault is open, or what any holds: the real vault and a duress vault erase exactly
/// alike, and so does a device with no encrypted vault at all.
///
/// **Steps**, in order. The erase is journaled (`VaultStorageState.Transition.erasing`) and every step is safe to
/// repeat, so an erase the app was stopped in the middle of finishes at the next launch, before any store opens
/// (`VaultStorageRecovery` reports `.erasing`, and the app calls `erase()` again):
///
/// 1. Locks the store session, so nothing reads or writes a vault while it's erased, and lets go of the plain store,
///    if one is open, so its database closes before its files go.
/// 2. Journals the erase. If the journal can't be written, perhaps because the disk is full, it does step 3 first,
///    which frees space, and then tries again: an erase mustn't depend on being able to write.
/// 3. Removes every copy of a vault: the encrypted file first, then its temp files and its lock file, the plain
///    store's files, and plain stores set aside because they couldn't be opened, which are plaintext copies. Nothing
///    can open a vault from here on. It holds the encrypted file's lock while it does, if it can, so a save underway
///    in an extension can't put the file back: a save reads the file under the lock, and fails if there isn't one.
/// 4. Deletes the keychain items: the killphrase and search passphrase HMAC keys, the backup password and its
///    record, and the count of attempts at the App Lock Password.
/// 5. Removes the plain store's pending rehash files, which hold phrases in plaintext.
/// 6. Clears the QuickType identity store and reloads the widgets' timelines.
/// 7. Creates a fresh, empty plain store, clears the journal, which removes the storage state, and switches the store
///    session to the new store.
///
/// If a step fails, the erase stops and throws, with the session still locked, so nothing reads or writes the half
/// erased store: calling `erase()` again, or launching again, carries on from there.
///
/// What the app holds in memory is its own to reset once the erase is done: the vault's items, the backup password,
/// and the killphrase and search passphrase digesters, which were made from the keys this deletes.
///
/// See "Erasing after failed attempts" in `docs/on-device-encryption.md`. Never log, print or measure anything about
/// an erase: when it happens shows how many wrong passwords were tried.
public actor VaultEraser {
    /// The keychain items it deletes, apart from the attempt count, which `AppLockPasswordAttemptCounter` keeps.
    static let keychainKeys = [
        VaultIdentifiers.SecureStorageKey.killphraseKey,
        VaultIdentifiers.SecureStorageKey.searchPassphraseKey,
        VaultIdentifiers.SecureStorageKey.backupPassword,
        VaultIdentifiers.SecureStorageKey.backupPasswordMetadata,
    ]

    /// What the app does around an erase, outside storage. Each is called again if the erase is repeated.
    public struct Hooks: Sendable {
        /// Lets go of the plain store, if one is open, so its database closes before its files are deleted. The
        /// store session has already locked.
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
    private let session: VaultStoreSession
    private let secureStorage: any SecureStorage
    private let attemptCounter: AppLockPasswordAttemptCounter
    private let hooks: Hooks
    private let makePlainStore: @Sendable () throws -> PersistedLocalVaultStore
    /// The erase underway, which a second call waits for rather than starting another.
    private var erasing: Task<Void, any Error>?

    /// - Parameters:
    ///   - directory: The vault's storage directory.
    ///   - session: The store session the app reads and writes the vault through.
    ///   - secureStorage: The keychain the HMAC keys and the backup password are in.
    ///   - attemptCounter: The count of attempts at the App Lock Password.
    public init(
        directory: URL,
        session: VaultStoreSession,
        secureStorage: any SecureStorage,
        attemptCounter: AppLockPasswordAttemptCounter,
        hooks: Hooks,
    ) {
        self.init(
            directory: directory,
            fileSystem: LiveSlotFileSystem(),
            session: session,
            secureStorage: secureStorage,
            attemptCounter: attemptCounter,
            hooks: hooks,
            makePlainStore: {
                // Only opens: a store it couldn't open is never set aside, as that would keep a copy of it.
                try PersistedLocalVaultStoreFactory(storageDirectory: directory, recoveryMode: .openOnly)
                    .makeVaultStoreOrThrow()
            },
        )
    }

    init(
        directory: URL,
        fileSystem: any SlotFileSystem,
        session: VaultStoreSession,
        secureStorage: any SecureStorage,
        attemptCounter: AppLockPasswordAttemptCounter,
        hooks: Hooks,
        makePlainStore: @escaping @Sendable () throws -> PersistedLocalVaultStore,
    ) {
        self.directory = directory
        self.fileSystem = fileSystem
        self.session = session
        self.secureStorage = secureStorage
        self.attemptCounter = attemptCounter
        self.hooks = hooks
        self.makePlainStore = makePlainStore
    }
}

// MARK: - Erasing

extension VaultEraser {
    /// Erases every vault and leaves a fresh, empty plain store, which the store session then reads and writes.
    ///
    /// Call it after the tenth wrong App Lock Password in a row, when the user has turned erasing on
    /// (`VaultUnlockResult.wrongPassword(reachesEraseThreshold:)`), and at launch when recovery reports `.erasing`.
    /// It finishes an erase that was interrupted, and does nothing that isn't needed if there's nothing left to erase.
    ///
    /// Cancelling the task that called it doesn't stop it: an erase is never left half done on purpose.
    ///
    /// - Throws: Whatever stopped the erase. The session stays locked, and calling this again, or launching again,
    ///   finishes it.
    public func erase() async throws {
        if let erasing {
            return try await erasing.value
        }
        let task = Task { try await eraseEverything() }
        erasing = task
        defer { erasing = nil }
        try await task.value
    }

    private func eraseEverything() async throws {
        let stateFile = VaultStorageStateFile(directory: directory, fileSystem: fileSystem)
        await session.lock()
        await hooks.releasePlainStore()
        do {
            try journal(in: stateFile)
        } catch {
            try await removeEveryVault()
            try journal(in: stateFile)
        }
        try await removeEveryVault()
        try await deleteKeychainItems()
        try removePendingRehashFiles(stateFile: stateFile)
        await hooks.clearCredentialIdentities()
        await hooks.reloadWidgets()

        let store = try makePlainStore()
        try stateFile.write(.plain)
        await session.switchTo(.plain(store))
    }

    /// Journals the erase, keeping the rest of the state as it was, or as it's taken to be if it can't be read.
    private func journal(in stateFile: VaultStorageStateFile) throws {
        var state = (try? stateFile.read()) ?? VaultStorageState(mode: .password)
        guard state.transition != .erasing else { return }
        state.transition = .erasing
        try stateFile.write(state)
    }

    /// Removes every copy of a vault: the encrypted file and what goes with it, the plain store, and its archives.
    private func removeEveryVault() async throws {
        let directory = directory
        let fileSystem = fileSystem
        let file = EncryptedVaultFile(directory: directory, fileSystem: fileSystem)
        do {
            try await file.withLock { _ in try Self.removeVaultFiles(in: directory, fileSystem: fileSystem) }
        } catch {
            // The lock couldn't be taken, or removing failed under it. Removing the files is what makes this an erase,
            // so it goes ahead without the lock, and throws if it still fails.
            try Self.removeVaultFiles(in: directory, fileSystem: fileSystem)
        }
    }

    private static func removeVaultFiles(in directory: URL, fileSystem: any SlotFileSystem) throws {
        // The encrypted file first: that alone makes every vault in it unreadable.
        try fileSystem.removeItem(at: directory.appending(path: EncryptedVaultFile.fileName))
        let plainStoreFileNames = Set(
            PersistedLocalVaultStoreFactory.storeFileURLs(storageDirectory: directory).map(\.lastPathComponent),
        )
        // In order of name, so every erase takes the same steps.
        for url in try fileSystem.contentsOfDirectory(at: directory).sorted(by: { $0.path < $1.path }) {
            let name = url.lastPathComponent
            let holdsAVault = name.hasPrefix(EncryptedVaultFile.temporaryFilePrefix)
                || name == EncryptedVaultFile.lockFileName
                || plainStoreFileNames.contains(name)
                || name.hasPrefix(PersistedLocalVaultStoreArchives.directoryNamePrefix)
            if holdsAVault {
                try fileSystem.removeItem(at: url)
            }
        }
        // Attempted, not required: the files are gone once they're removed. If a power loss brought any back, the
        // journal would still say to erase them.
        try? fileSystem.synchronizeDirectory(at: directory)
    }

    private func deleteKeychainItems() async throws {
        for key in Self.keychainKeys {
            try await secureStorage.remove(key: key)
        }
        try await attemptCounter.reset()
    }

    /// Removes the pending rehash files, and temp files a crash left behind while writing the storage state.
    private func removePendingRehashFiles(stateFile: VaultStorageStateFile) throws {
        for url in PersistedLocalVaultStoreFactory.pendingRehashFileURLs(storageDirectory: directory) {
            try fileSystem.removeItem(at: url)
        }
        try stateFile.removeStrayTemporaryFiles()
        try? fileSystem.synchronizeDirectory(at: directory)
    }
}
