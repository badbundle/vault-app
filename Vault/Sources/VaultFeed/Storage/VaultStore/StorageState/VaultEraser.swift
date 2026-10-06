import Foundation
import FoundationExtensions
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
///    which frees space, and then tries again: an erase mustn't depend on being able to write. If that fails too, or
///    the app stops in between, there's no journal, but no vault either, and launch recovery finishes the erase. In
///    this case it removes the plain store before the encrypted file, so the app can't stop with the encrypted file
///    gone and a plain store left, which recovery would keep, as it could be the only copy of the vault.
/// 3. Removes every copy of a vault: the encrypted file first, then its temp files, the plain store's files, plain
///    stores set aside because they couldn't be opened, which are plaintext copies, and last the lock file. Nothing
///    can open a vault from here on. It holds the encrypted file's lock while it does, if it can, so a save underway
///    in an extension can't put the file back: a save reads the file under the lock, and fails if there isn't one.
/// 4. Deletes every keychain item (`VaultIdentifiers.SecureStorageKey`): the killphrase and search passphrase HMAC
///    keyrings, this device's own keys and those restored backups brought, the backup password and its record, the
/// count of attempts at the App Lock Password, the wrap stamp,
///    which shows a password vault was used and about when, and the device key, which opens the vault while the
///    password is off.
/// 5. Clears the vault's settings still kept on the device: the last backup event, the auto-backup configuration,
///    which says where the backups are, and the PDF backup's hint. Then whatever holds them in memory forgets them
///    too (a hook). It turns off erasing after failed passwords too, which only means anything with a password.
/// 6. Removes the plain store's pending rehash files, which hold phrases in plaintext, backup PDFs left in the app's
///    temporary directory, and the file the count of attempts at the App Lock Password takes its lock on, which step
///    4 makes if it isn't there. Nothing makes that file again until a password is set.
/// 7. Clears the QuickType identity store, trying a few times, and reloads the widgets' timelines. If QuickType still
///    can't be cleared, the erase carries on: while the password is on, the store is kept empty already, and a store
///    that's stuck mustn't leave the vaults half erased.
/// 8. Checks, holding the lock, that no writer that had stalled has put the encrypted file back.
/// 9. Creates a fresh, empty plain store, clears the journal, which removes the storage state, and switches the store
///    session to the new store.
///
/// If a step fails, the erase stops and throws, with the session still locked, so nothing reads or writes the half
/// erased store: calling `erase()` again, or launching again, carries on from there. Unlocking refuses while the
/// journal says an erase is underway (`VaultUnlockError.erasing`).
///
/// What the app holds in memory from the vault itself is its own to reset once the erase is done: the vault's items,
/// the backup password, and the killphrase and search passphrase digesters, which were made from the keys this
/// deletes.
///
/// See "Erasing after failed attempts" in `docs/on-device-encryption.md`. Never log, print or measure anything about
/// an erase: when it happens shows how many wrong passwords were tried.
public actor VaultEraser {
    /// What the app does around an erase, outside storage. Each is called again if the erase is repeated.
    public struct Hooks: Sendable {
        /// Lets go of the plain store, if one is open, so its database closes before its files are deleted. The
        /// store session has already locked.
        public var releasePlainStore: @Sendable () async -> Void
        /// Empties the QuickType identity store, which holds every visible code's issuer and account name. If it
        /// throws, it's tried again a few times (`credentialIdentityAttempts`), and then the erase carries on.
        public var clearCredentialIdentities: @Sendable () async throws -> Void
        /// Reloads the widgets' timelines, so none keeps showing a code.
        public var reloadWidgets: @Sendable () async -> Void
        /// Makes whatever holds the vault's settings in memory forget them, once they're cleared from the defaults:
        /// the auto-backup service's configuration and its providers' folders, and the last backup event the app
        /// shows. Otherwise the next backup could go where the erased vault's went, and its retention clean-up
        /// delete them.
        public var forgetVaultSettings: @Sendable () async -> Void

        public init(
            releasePlainStore: @escaping @Sendable () async -> Void,
            clearCredentialIdentities: @escaping @Sendable () async throws -> Void,
            reloadWidgets: @escaping @Sendable () async -> Void,
            forgetVaultSettings: @escaping @Sendable () async -> Void,
        ) {
            self.releasePlainStore = releasePlainStore
            self.clearCredentialIdentities = clearCredentialIdentities
            self.reloadWidgets = reloadWidgets
            self.forgetVaultSettings = forgetVaultSettings
        }
    }

    private let directory: URL
    private let fileSystem: any SlotFileSystem
    private let session: VaultStoreSession
    private let secureStorage: any SecureStorage
    private let attemptCounter: AppLockPasswordAttemptCounter
    private let wrapStamps: any VaultWrapStampStorage
    private let deviceKeyStore: any VaultDeviceKeyStoring
    private let appLockSettings: AppLockSettingsStore
    private let defaults: Defaults
    private let temporaryDirectory: URL
    private let hooks: Hooks
    private let makePlainStore: @Sendable () throws -> PersistedLocalVaultStore
    /// The erase underway, which a second call waits for rather than starting another.
    private var erasing: Task<PersistedLocalVaultStore, any Error>?

    /// - Parameters:
    ///   - directory: The vault's storage directory.
    ///   - session: The store session the app reads and writes the vault through.
    ///   - secureStorage: The keychain the HMAC keys and the backup password are in.
    ///   - attemptCounter: The count of attempts at the App Lock Password.
    ///   - appLockSettings: The app lock's settings, with erasing after failed passwords.
    ///   - defaults: The app's defaults, where the last backup event, the auto-backup configuration and the PDF
    ///     backup's hint are.
    ///   - temporaryDirectory: The app's temporary directory, where a PDF backup is written while the share sheet has
    ///     it (`BackupPDFTemporaryFiles`).
    ///   - makePlainStore: Makes the fresh, empty plain store the erase leaves, if not the SQLite store in `directory`:
    ///     the Mac's is in memory, as it never keeps a vault that isn't encrypted (docs/mac-app.md).
    public init(
        directory: URL,
        session: VaultStoreSession,
        secureStorage: any SecureStorage,
        attemptCounter: AppLockPasswordAttemptCounter,
        appLockSettings: AppLockSettingsStore,
        defaults: Defaults,
        temporaryDirectory: URL,
        hooks: Hooks,
        makePlainStore: (@Sendable () throws -> PersistedLocalVaultStore)? = nil,
    ) {
        self.init(
            directory: directory,
            fileSystem: LiveSlotFileSystem(),
            session: session,
            secureStorage: secureStorage,
            attemptCounter: attemptCounter,
            wrapStamps: VaultWrapStampKeychainStorage(),
            deviceKeyStore: VaultDeviceKeychainStore(),
            appLockSettings: appLockSettings,
            defaults: defaults,
            temporaryDirectory: temporaryDirectory,
            hooks: hooks,
            makePlainStore: makePlainStore ?? {
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
        wrapStamps: any VaultWrapStampStorage,
        deviceKeyStore: any VaultDeviceKeyStoring,
        appLockSettings: AppLockSettingsStore,
        defaults: Defaults,
        temporaryDirectory: URL,
        hooks: Hooks,
        makePlainStore: @escaping @Sendable () throws -> PersistedLocalVaultStore,
    ) {
        self.directory = directory
        self.fileSystem = fileSystem
        self.session = session
        self.secureStorage = secureStorage
        self.attemptCounter = attemptCounter
        self.wrapStamps = wrapStamps
        self.deviceKeyStore = deviceKeyStore
        self.appLockSettings = appLockSettings
        self.defaults = defaults
        self.temporaryDirectory = temporaryDirectory
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
    /// - Returns: The fresh plain store, which the session now reads and writes.
    /// - Throws: Whatever stopped the erase. The session stays locked, and calling this again, or launching again,
    ///   finishes it.
    @discardableResult
    public func erase() async throws -> PersistedLocalVaultStore {
        if let erasing {
            return try await erasing.value
        }
        let task = Task { try await eraseEverything() }
        erasing = task
        defer { erasing = nil }
        return try await task.value
    }

    private func eraseEverything() async throws -> PersistedLocalVaultStore {
        let stateFile = VaultStorageStateFile(directory: directory, fileSystem: fileSystem)
        await session.lock()
        await hooks.releasePlainStore()
        do {
            try journal(in: stateFile)
        } catch {
            try await removeEveryVault(encryptedFileLast: true)
            try journal(in: stateFile)
        }
        try await removeEveryVault()
        try await deleteKeychainItems()
        await Self.clearVaultSettings(in: defaults)
        appLockSettings.erasesAfterFailedPasswords = false
        await hooks.forgetVaultSettings()
        try removeFilesLeftBehind(stateFile: stateFile)
        try await attemptCounter.removeLockFile()
        await clearCredentialIdentities()
        await hooks.reloadWidgets()
        try await removeEveryVault(includingThePlainStore: false)

        let store = try makePlainStore()
        try stateFile.write(.plain)
        await session.switchTo(.plain(store))
        return store
    }

    /// Journals the erase, keeping the rest of the state as it was, or as it's taken to be if it can't be read.
    private func journal(in stateFile: VaultStorageStateFile) throws {
        var state = (try? stateFile.read()) ?? VaultStorageState(mode: .password)
        guard state.transition != .erasing else { return }
        state.transition = .erasing
        try stateFile.write(state)
    }

    /// Removes every copy of a vault: the encrypted file and what goes with it, and the plain store and its
    /// archives, unless the plain store is the fresh one.
    ///
    /// - Parameter encryptedFileLast: Whether to remove the encrypted file after the plain store rather than before.
    private func removeEveryVault(includingThePlainStore: Bool = true, encryptedFileLast: Bool = false) async throws {
        let directory = directory
        let fileSystem = fileSystem
        let file = EncryptedVaultFile(directory: directory, fileSystem: fileSystem)
        do {
            try await file.withLock { _ in
                try Self.removeVaultFiles(
                    in: directory,
                    fileSystem: fileSystem,
                    includingThePlainStore: includingThePlainStore,
                    encryptedFileLast: encryptedFileLast,
                )
            }
        } catch {
            // The lock couldn't be taken, or removing failed under it. Removing the files is what makes this an erase,
            // so it goes ahead without the lock, and throws if it still fails.
            try Self.removeVaultFiles(
                in: directory,
                fileSystem: fileSystem,
                includingThePlainStore: includingThePlainStore,
                encryptedFileLast: encryptedFileLast,
            )
        }
    }

    private static func removeVaultFiles(
        in directory: URL,
        fileSystem: any SlotFileSystem,
        includingThePlainStore: Bool,
        encryptedFileLast: Bool,
    ) throws {
        let encryptedFile = directory.appending(path: EncryptedVaultFile.fileName)
        if !encryptedFileLast {
            // The encrypted file first: that alone makes every vault in it unreadable.
            try fileSystem.removeItem(at: encryptedFile)
        }
        let plainStoreFileNames = Set(
            PersistedLocalVaultStoreFactory.storeFileURLs(storageDirectory: directory).map(\.lastPathComponent),
        )
        // In order of name, so every erase takes the same steps.
        for url in try fileSystem.contentsOfDirectory(at: directory).sorted(by: { $0.path < $1.path }) {
            let name = url.lastPathComponent
            let isTemporary = name.hasPrefix(EncryptedVaultFile.temporaryFilePrefix)
            let isPlain = plainStoreFileNames.contains(name)
                || name.hasPrefix(PersistedLocalVaultStoreArchives.directoryNamePrefix)
            if isTemporary || (includingThePlainStore && isPlain) {
                try fileSystem.removeItem(at: url)
            }
        }
        if encryptedFileLast {
            try fileSystem.removeItem(at: encryptedFile)
        }
        // The lock file only once the encrypted file is gone: a writer that found no lock file would make a new one,
        // take it without waiting for this one, and could save over a file that was still there.
        try fileSystem.removeItem(at: directory.appending(path: EncryptedVaultFile.lockFileName))
        // Attempted, not required: the files are gone once they're removed. If a power loss brought any back, the
        // journal would still say to erase them.
        try? fileSystem.synchronizeDirectory(at: directory)
    }

    private func deleteKeychainItems() async throws {
        for key in VaultIdentifiers.SecureStorageKey.allCases {
            try await delete(key)
        }
    }

    /// Deletes a keychain item, wherever it's kept. Every item is erased, and none kept: they all belong to the vault
    /// or show it existed. An item added to `SecureStorageKey` doesn't build until it's decided here what an erase
    /// does with it.
    private func delete(_ key: VaultIdentifiers.SecureStorageKey) async throws {
        switch key {
        case .backupPassword, .backupPasswordMetadata, .killphraseKey, .searchPassphraseKey:
            try await secureStorage.remove(key: key.keychainService)
        case .killphraseBackupKeys, .searchPassphraseBackupKeys:
            // The rest of the keyrings, the keys restored backups brought: they check the erased vaults' phrases, and
            // show backups were restored here.
            try await secureStorage.remove(key: key.keychainService)
        case .appLockPasswordAttempts:
            try await attemptCounter.reset()
        case .vaultWrapStamp:
            // It shows a password vault was used on this device, and about when one last opened (MANIFESTO C6).
            try wrapStamps.remove()
        case .vaultDeviceKey:
            // It opens the vault while the password is off. With the file gone it opens nothing, but it shows the
            // password was turned off.
            try deviceKeyStore.removeDeviceKey()
        }
    }

    /// How many times the QuickType identity store is tried before an erase carries on without it.
    static let credentialIdentityAttempts = 3

    /// Empties the QuickType identity store, trying up to `credentialIdentityAttempts` times. It never stops the
    /// erase: while the password is on, the store is kept empty already.
    private func clearCredentialIdentities() async {
        var attempts = 0
        while attempts < Self.credentialIdentityAttempts, (try? await hooks.clearCredentialIdentities()) == nil {
            attempts += 1
        }
    }

    /// Clears the vault's settings that are still kept on the device, rather than in the vault itself: they'd show an
    /// erased vault had been there, and where its backups are.
    @MainActor
    private static func clearVaultSettings(in defaults: Defaults) {
        defaults.clear(Key<VaultBackupEvent>(VaultIdentifiers.Backup.lastBackupEvent))
        defaults.clear(Key<AutoBackupConfiguration>(VaultIdentifiers.AutoBackup.configuration))
        defaults.clear(Key<String>(VaultIdentifiers.Preferences.PDF.userHint))
    }

    /// Removes the pending rehash files, temp files a crash left behind while writing the storage state, and backup
    /// PDFs left in the app's temporary directory.
    private func removeFilesLeftBehind(stateFile: VaultStorageStateFile) throws {
        for url in PersistedLocalVaultStoreFactory.pendingRehashFileURLs(storageDirectory: directory) {
            try fileSystem.removeItem(at: url)
        }
        try stateFile.removeStrayTemporaryFiles()
        try? fileSystem.synchronizeDirectory(at: directory)
        BackupPDFTemporaryFiles(fileManager: .default, directory: temporaryDirectory).deleteAll()
    }
}
