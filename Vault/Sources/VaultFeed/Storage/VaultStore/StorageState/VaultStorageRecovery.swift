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
/// - **Turning the password off, or back on** (`VaultPasswordChangeService`): it tries the device key on every slot.
///   If one opens, the vault's key is wrapped with the device key, so the password is off; if none does, it's on.
///   Either way the vault is intact: the rekey is a single rename.
///
/// It never deletes the only copy of anything: an encrypted file goes only if the plain store is there to be the
/// vault, and the plain store only if there's an encrypted file the size of one. See "Migration: plain to
/// encrypted" and "Turning the password off" in `docs/on-device-encryption.md`.
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
    }

    private let directory: URL
    private let fileSystem: any SlotFileSystem
    private let deviceKeyStore: any VaultDeviceKeyStoring

    public init(directory: URL, deviceKeyStore: any VaultDeviceKeyStoring = VaultDeviceKeychainStore()) {
        self.init(directory: directory, fileSystem: LiveSlotFileSystem(), deviceKeyStore: deviceKeyStore)
    }

    init(
        directory: URL,
        fileSystem: any SlotFileSystem,
        deviceKeyStore: any VaultDeviceKeyStoring = VaultDeviceKeychainStore(),
    ) {
        self.directory = directory
        self.fileSystem = fileSystem
        self.deviceKeyStore = deviceKeyStore
    }

    /// Finishes or undoes any change underway, apart from clearing the system surfaces.
    ///
    /// - Returns: How the vault is stored now.
    /// - Throws: If the state can't be read or a step fails, `Failure` if deleting would risk the only copy of the
    ///   vault. Nothing should open a store then.
    public func recoverAtLaunch() throws -> VaultStorageState.Mode {
        let stateFile = VaultStorageStateFile(directory: directory, fileSystem: fileSystem)
        try stateFile.removeStrayTemporaryFiles()
        var state = try stateFile.read()
        if state.transition == .turningOff || state.transition == .turningOn {
            let wasTurningOn = state.transition == .turningOn
            let passwordIsOff = try deviceKeyOpensASlot()
            state.mode = passwordIsOff ? .deviceKey : .password
            state.transition = nil
            try stateFile.write(state)
            if wasTurningOn, !passwordIsOff {
                try? deviceKeyStore.removeDeviceKey()
            }
            return state.mode
        }
        switch state.mode {
        case .plain:
            try removeEncryptedFiles()
            if state != .plain {
                try stateFile.write(.plain)
            }
            return .plain
        case .password:
            if case let .deletingPlainStore(archives) = state.transition {
                try deletePlainStore(archives: archives)
                state.transition = .clearingSystemSurfaces
                try stateFile.write(state)
            }
            return .password
        case .deviceKey:
            return .deviceKey
        }
    }

    /// Whether the device key opens any slot of the file.
    private func deviceKeyOpensASlot() throws -> Bool {
        guard let deviceKey = try deviceKeyStore.deviceKey() else { return false }
        let url = EncryptedVaultFile(directory: directory, fileSystem: fileSystem).url
        guard let bytes = try fileSystem.contents(of: url) else { throw Failure.encryptedFileMissing }
        let file = try VaultSlotFile(bytes: bytes)
        return VaultSlotFile.slotIndices.contains { (try? file.openSlot($0, with: .device(deviceKey))) != nil }
    }

    /// Clears the QuickType identity store and reloads the widgets, if a committed conversion hadn't yet, then clears
    /// the journal. Call it once at launch, after `recoverAtLaunch()`. It's safe to repeat.
    public func finishClearingSystemSurfaces(_ clear: @Sendable () async -> Void) async throws {
        let stateFile = VaultStorageStateFile(directory: directory, fileSystem: fileSystem)
        guard try stateFile.read().transition == .clearingSystemSurfaces else { return }
        await clear()
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
