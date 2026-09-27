import Foundation

/// Finishes or undoes a change of storage mode that the app was stopped in the middle of, when it next launches.
///
/// Only the app runs it, before it opens any store. An extension that finds a change underway treats the vault as
/// locked instead (`VaultStorageState.isPlain(inDirectory:)`). What it does depends on the journal
/// (`VaultStorageState.transition`):
///
/// - **Encrypting**, or plain with a stray encrypted file: the plain store was never touched and is still the vault.
///   It deletes the encrypted file and any temp files, and goes back to plain. The user was never told the password
///   was set.
/// - **Deleting the plain store**: the encrypted vault has committed. It finishes deleting the plain store's files,
///   its pending rehash files and the confirmed archives. That's safe to repeat.
/// - **Clearing the system surfaces**: the app then clears QuickType and reloads the widgets
///   (`finishClearingSystemSurfaces(_:)`), once it can.
/// - **Erasing**: it leaves the files alone and reports `.erasing`. The app opens no store, and finishes the erase
///   with `VaultEraser`, which needs the keychain and the app's hooks as well as the files.
/// - **An encrypted mode with no vault left**, neither the encrypted file nor the plain store, and no journal: an
///   erase that removed the vault but couldn't journal it, if the count of wrong attempts has reached the erase
///   threshold, so it reports `.erasing`. Otherwise nothing shows an erase was meant: a restore or a move to another
///   iPhone may have brought back the state without the file. Erasing then would delete the keychain items, and
///   recovery would later delete the file if it turned up, so it touches nothing and throws `.vaultMissing`. The
///   failure screen says how to restore it, and offers to erase and start again only once the user confirms.
/// - **Turning the password off, or back on** (`VaultPasswordChangeService`): it tries the device key on every slot.
///   If one opens, the vault's key is wrapped with the device key, so the password is off; if none does, it's on.
///   Either way the vault is intact: the rekey is a single rename. While the app runs, the change service and the
///   unlock path settle one the same way (`settleTurningThePasswordOffOrOn()`).
///
/// Every change to the state is made holding `vault-slots.lock`, so none is lost to an extension raising the unlock
/// deadline, and no rekey changes the file while the device key is tried on it.
///
/// It never deletes the only copy of anything: an encrypted file goes only if the plain store is there to be the
/// vault, the plain store only if there's an encrypted file the size of one, and the device key only once it's been
/// shown to open nothing. See "Migration: plain to encrypted" and "Turning the password off" in
/// `docs/on-device-encryption.md`.
public struct VaultStorageRecovery: Sendable {
    public enum Failure: Error, Equatable, Sendable {
        /// The state says plain, but there's an encrypted file and no plain store: deleting the encrypted file might
        /// delete the only copy of the vault, so nothing is deleted.
        case encryptedFileWithoutPlainStore
        /// The state says the conversion committed, but there's no encrypted file the size of one: deleting the
        /// plain store might delete the only copy of the vault, so nothing is deleted.
        case plainStoreWithoutEncryptedFile
        /// The state says the vault is encrypted, but there's no encrypted file.
        case encryptedFileMissing
        /// The password is off, and the device key that opens the vault isn't in the keychain: for example, after an
        /// unencrypted computer backup was restored onto another iPhone, which doesn't bring keychain items with it.
        case deviceKeyMissing
        /// The encrypted file can't be read until the device is unlocked, so a turn off or on the app was stopped in
        /// the middle of can't be settled yet. Nothing changed.
        case fileUnreadableWhileLocked
        /// The state says the vault is encrypted, but neither the encrypted file nor the plain store is there, and
        /// nothing shows an erase was meant: no journal, and fewer wrong attempts than the erase threshold. Nothing
        /// was changed or deleted. Only the user can decide to erase and start again.
        case vaultMissing
    }

    /// How the vault is stored, once recovery has finished or undone what it could.
    public enum Outcome: Equatable, Sendable {
        /// The plain store is the vault.
        case plain
        /// The encrypted file is the vault, and the App Lock Password opens it.
        case password
        /// The encrypted file is the vault, and the device key opens it: the password is off.
        case deviceKey
        /// An erase was underway. Open no store: finish it with `VaultEraser.erase()` first, which leaves a fresh,
        /// empty plain store.
        case erasing
    }

    private let directory: URL
    private let fileSystem: any SlotFileSystem
    private let deviceKeyStore: any VaultDeviceKeyStoring
    private let attemptStorage: any AppLockPasswordAttemptStorage

    public init(directory: URL, deviceKeyStore: any VaultDeviceKeyStoring = VaultDeviceKeychainStore()) {
        self.init(directory: directory, fileSystem: LiveSlotFileSystem(), deviceKeyStore: deviceKeyStore)
    }

    /// - Parameter attemptStorage: Where the count of wrong attempts is, which shows whether an erase was meant when
    ///   the vault is gone and no erase was journaled.
    init(
        directory: URL,
        fileSystem: any SlotFileSystem,
        deviceKeyStore: any VaultDeviceKeyStoring = VaultDeviceKeychainStore(),
        attemptStorage: any AppLockPasswordAttemptStorage = AppLockPasswordAttemptKeychainStorage(),
    ) {
        self.directory = directory
        self.fileSystem = fileSystem
        self.deviceKeyStore = deviceKeyStore
        self.attemptStorage = attemptStorage
    }

    private var stateFile: VaultStorageStateFile {
        VaultStorageStateFile(directory: directory, fileSystem: fileSystem)
    }

    /// Finishes or undoes any change underway, apart from clearing the system surfaces.
    ///
    /// It can run while the device is locked, if the app launches in the background. The one thing it can't do then
    /// is settle a turn off or on, which needs to read the file. The file is unreadable then only if it's in the
    /// password form, as turning the password off makes it readable after the first unlock, and turning it on makes
    /// it unreadable while locked again. So the password is on, and the journal stays for the unlock path or the next
    /// launch to settle.
    ///
    /// - Returns: How the vault is stored now, or `.erasing` if an erase is still to finish.
    /// - Throws: If the state can't be read or a step fails, `Failure` if deleting would risk the only copy of the
    ///   vault, `.deviceKeyMissing` if the password is off and there's no device key, or `.vaultMissing` if there's no
    ///   vault and nothing shows an erase was meant. Nothing should open a store then.
    public func recoverAtLaunch() throws -> Outcome {
        let (state, step) = try stateFile.updateBlockingTheThread { state -> LaunchStep in
            try stateFile.removeStrayTemporaryFiles()
            guard state.transition != .erasing else { return .erasing }
            if state.mode != .plain, try !anyVaultIsLeft() {
                // An erase removed the vault but couldn't journal that it had, as it can if the disk is full: then the
                // count of wrong attempts shows it was meant, and it has to finish. Anything else is left for the
                // user to decide.
                guard reachedTheEraseThreshold() else { throw Failure.vaultMissing }
                return .erasing
            }
            if state.isTurningThePasswordOffOrOn {
                return try .settled(settleTurning(&state))
            }
            switch state.mode {
            case .plain:
                try removeEncryptedFiles()
                state = .plain
            case .password:
                if case let .deletingPlainStore(archives) = state.transition {
                    try deletePlainStore(archives: archives)
                    state.transition = .clearingSystemSurfaces
                }
            case .deviceKey:
                break
            }
            return .recovered
        }
        switch step {
        case .erasing:
            return .erasing
        case .settled(.fileUnreadableWhileLocked):
            return .password
        case .settled, .recovered:
            break
        }
        switch state.mode {
        case .plain:
            return .plain
        case .password:
            if case .settled(.opensNothing) = step {
                try? deviceKeyStore.removeDeviceKey()
            } else {
                removeDeviceKeyIfItOpensNothing()
            }
            return .password
        case .deviceKey:
            guard try deviceKeyStore.deviceKey() != nil else { throw Failure.deviceKeyMissing }
            return .deviceKey
        }
    }

    /// What launch recovery did under the lock.
    private enum LaunchStep {
        case recovered
        /// It settled a turn off or on, from what trying the device key found.
        case settled(DeviceKeyTrial)
        case erasing
    }

    /// Whether the count of wrong attempts in a row has reached the erase threshold. If it can't be read, as while
    /// the device is locked, nothing shows it has.
    private func reachedTheEraseThreshold() -> Bool {
        guard let record = try? attemptStorage.load() else { return false }
        return record.count >= AppLockPasswordAttemptCounter.eraseThreshold
    }

    /// Whether there's still a vault to open: the encrypted file, or the plain store.
    private func anyVaultIsLeft() throws -> Bool {
        let names = try Set(fileSystem.contentsOfDirectory(at: directory).map(\.lastPathComponent))
        let plainStoreFile = PersistedLocalVaultStoreFactory.storeFileURLs(storageDirectory: directory)[0]
        return names.contains(EncryptedVaultFile.fileName) || names.contains(plainStoreFile.lastPathComponent)
    }

    /// Settles a turn off or on that was stopped in the middle, while the app runs, as launch recovery does. Only the
    /// app calls it, and only while no change is underway: `VaultPasswordChangeService` runs it.
    ///
    /// - Returns: How the vault is stored now.
    /// - Throws: `Failure.fileUnreadableWhileLocked` if the device is locked and the file can't be read, and nothing
    ///   changed.
    func settleTurningThePasswordOffOrOn() async throws -> VaultStorageState.Mode {
        let (state, trial) = try await stateFile.update { state -> DeviceKeyTrial? in
            guard state.isTurningThePasswordOffOrOn else { return nil }
            return try settleTurning(&state)
        }
        if trial == .fileUnreadableWhileLocked {
            throw Failure.fileUnreadableWhileLocked
        }
        if state.mode == .password, trial == .opensNothing {
            // It opens nothing now. If deleting it fails, the next launch tries again.
            try? deviceKeyStore.removeDeviceKey()
        }
        return state.mode
    }

    /// What trying the device key on every slot of the file found.
    private enum DeviceKeyTrial {
        case noDeviceKey
        case opensNothing
        case opensASlot
        /// The device is locked, and the file is readable only while it's unlocked.
        case fileUnreadableWhileLocked
    }

    /// Settles a turn off or on in `state`, from what the device key opens. Run it holding `vault-slots.lock`, so no
    /// rekey changes the file meanwhile. If the file can't be read while the device is locked, `state` is left as it
    /// was.
    private func settleTurning(_ state: inout VaultStorageState) throws -> DeviceKeyTrial {
        let trial = try tryDeviceKey()
        switch trial {
        case .fileUnreadableWhileLocked:
            break
        case .opensASlot:
            state.mode = .deviceKey
            state.transition = nil
        case .noDeviceKey, .opensNothing:
            state.mode = .password
            state.transition = nil
        }
        return trial
    }

    private func tryDeviceKey() throws -> DeviceKeyTrial {
        guard let deviceKey = try deviceKeyStore.deviceKey() else { return .noDeviceKey }
        let url = EncryptedVaultFile(directory: directory, fileSystem: fileSystem).url
        let bytes: Data?
        do {
            bytes = try fileSystem.contents(of: url)
        } catch let error where Self.isUnreadableWhileLocked(error) {
            return .fileUnreadableWhileLocked
        }
        guard let bytes else { throw Failure.encryptedFileMissing }
        let file = try VaultSlotFile(bytes: bytes)
        let opensASlot = VaultSlotFile.slotIndices
            .contains { (try? file.openSlot($0, with: .device(deviceKey))) != nil }
        return opensASlot ? .opensASlot : .opensNothing
    }

    /// Deletes a device key left over with the password on, from a turn off that failed or a deletion that did, once
    /// it's shown to open no slot. If the file can't be read, it stays until the next launch.
    private func removeDeviceKeyIfItOpensNothing() {
        guard (try? tryDeviceKey()) == .opensNothing else { return }
        try? deviceKeyStore.removeDeviceKey()
    }

    /// Whether reading failed because the file's protection keeps it unreadable while the device is locked: iOS
    /// refuses to open it (`EPERM`), which Foundation reports as having no permission to read it.
    static func isUnreadableWhileLocked(_ error: any Error) -> Bool {
        let error = error as NSError
        switch error.domain {
        case NSCocoaErrorDomain:
            return error.code == CocoaError.fileReadNoPermission.rawValue
        case NSPOSIXErrorDomain:
            return error.code == Int(EPERM)
        default:
            return false
        }
    }

    /// Clears the QuickType identity store and reloads the widgets, if a committed conversion hadn't yet, then clears
    /// the journal. Call it once at launch, after `recoverAtLaunch()`. It's safe to repeat.
    ///
    /// If `clear` throws, the journal stays, so the next launch tries again.
    public func finishClearingSystemSurfaces(_ clear: @Sendable () async throws -> Void) async throws {
        let stateFile = VaultStorageStateFile(directory: directory, fileSystem: fileSystem)
        guard try stateFile.read().transition == .clearingSystemSurfaces else { return }
        try await clear()
        // Read again: an unlock may have raised the deadline while clearing.
        try await stateFile.update { state in
            if state.transition == .clearingSystemSurfaces {
                state.transition = nil
            }
        }
    }

    /// Deletes the encrypted file and its temp files, if the plain store is there to be the vault.
    func removeEncryptedFiles() throws {
        let contents = try fileSystem.contentsOfDirectory(at: directory)
        let encryptedFiles = contents.filter {
            $0.lastPathComponent == EncryptedVaultFile.fileName
                || $0.lastPathComponent.hasPrefix(EncryptedVaultFile.temporaryFilePrefix)
        }
        guard !encryptedFiles.isEmpty else { return }
        let plainStoreFile = PersistedLocalVaultStoreFactory.storeFileURLs(storageDirectory: directory)[0]
        guard contents.contains(where: { $0.lastPathComponent == plainStoreFile.lastPathComponent }) else {
            throw Failure.encryptedFileWithoutPlainStore
        }
        for url in encryptedFiles {
            try fileSystem.removeItem(at: url)
        }
        try? fileSystem.synchronizeDirectory(at: directory)
    }

    /// Deletes the plain store's files, its pending rehash files, and the named archives, each skipped if it's
    /// already gone: but only if the encrypted file is there, and the size of one.
    ///
    /// It checks the size rather than reading the file, because the file can only be read while the device is
    /// unlocked, and the app can launch in the background while it's locked. The conversion verified the file before
    /// it committed, and nothing but a rekey or a save replaces it after that, both verified too.
    func deletePlainStore(archives: [String]) throws {
        let encryptedFile = EncryptedVaultFile(directory: directory, fileSystem: fileSystem)
        guard let size = try fileSystem.fileSize(of: encryptedFile.url), VaultSlotFile.isPossibleFileSize(size) else {
            throw Failure.plainStoreWithoutEncryptedFile
        }
        let urls = PersistedLocalVaultStoreFactory.storeFileURLs(storageDirectory: directory)
            + PersistedLocalVaultStoreFactory.pendingRehashFileURLs(storageDirectory: directory)
            + archives.map { directory.appending(path: $0) }
        for url in urls {
            try fileSystem.removeItem(at: url)
        }
        try? fileSystem.synchronizeDirectory(at: directory)
    }
}
