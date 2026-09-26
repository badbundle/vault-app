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
///
/// It never deletes the only copy of anything: an encrypted file goes only if the plain store is there to be the
/// vault. See "Migration: plain to encrypted" in `docs/on-device-encryption.md`.
public struct VaultStorageRecovery: Sendable {
    public enum Failure: Error, Equatable, Sendable {
        /// The state says plain, but there's an encrypted file and no plain store: deleting the encrypted file might
        /// delete the only copy of the vault, so nothing is deleted.
        case encryptedFileWithoutPlainStore
    }

    private let directory: URL
    private let fileSystem: any SlotFileSystem

    public init(directory: URL) {
        self.init(directory: directory, fileSystem: LiveSlotFileSystem())
    }

    init(directory: URL, fileSystem: any SlotFileSystem) {
        self.directory = directory
        self.fileSystem = fileSystem
    }

    /// Finishes or undoes any change underway.
    ///
    /// - Returns: How the vault is stored now.
    /// - Throws: If the state can't be read or a step fails, `Failure` if deleting would risk the only copy of the
    ///   vault. Nothing should open a store then.
    public func recoverAtLaunch() throws -> VaultStorageState.Mode {
        let stateFile = VaultStorageStateFile(directory: directory, fileSystem: fileSystem)
        try stateFile.removeStrayTemporaryFiles()
        var state = try stateFile.read()
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
                state.transition = nil
                try stateFile.write(state)
            }
            return .password
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
        try fileSystem.synchronizeDirectory(at: directory)
    }

    /// Deletes the plain store's files, its pending rehash files, and the named archives. Each is skipped if it's
    /// already gone.
    func deletePlainStore(archives: [String]) throws {
        let urls = PersistedLocalVaultStoreFactory.storeFileURLs(storageDirectory: directory)
            + PersistedLocalVaultStoreFactory.pendingRehashFileURLs(storageDirectory: directory)
            + archives.map { directory.appending(path: $0) }
        for url in urls {
            try fileSystem.removeItem(at: url)
        }
        try fileSystem.synchronizeDirectory(at: directory)
    }
}
