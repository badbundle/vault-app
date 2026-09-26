import Foundation

/// The encrypted vault file, `vault-slots.v1`, and how it's read and replaced.
///
/// Every writer, in the app or an extension, holds `vault-slots.lock` with `flock` while it reads and replaces the
/// file, so they take turns. A replacement never overwrites the only copy of anything:
///
/// 1. The new file is written to a temp file, `.vault-slots.tmp-<random>`, and flushed with `F_FULLFSYNC`.
/// 2. It's read back and verified: it must match what was written byte for byte, and the writer checks that its
///    slot opens to what it saved.
/// 3. It's renamed over `vault-slots.v1`, which replaces every slot in one step. Then the directory is flushed.
///
/// A failure before the rename removes the temp file and leaves the old file as it was. A crash before the rename
/// leaves a temp file behind, which `open()` removes. See "Crash safety" in `docs/on-device-encryption.md`.
struct EncryptedVaultFile: Sendable {
    static let fileName = "vault-slots.v1"
    static let lockFileName = "vault-slots.lock"
    static let temporaryFilePrefix = ".vault-slots.tmp-"

    /// The directory the file is in.
    let directory: URL
    let fileSystem: any SlotFileSystem

    init(directory: URL, fileSystem: any SlotFileSystem = LiveSlotFileSystem()) {
        self.directory = directory
        self.fileSystem = fileSystem
    }

    var url: URL {
        directory.appending(path: Self.fileName)
    }

    var lockURL: URL {
        directory.appending(path: Self.lockFileName)
    }

    /// Reads the file to unlock a vault from it, first removing any temp files a crash left behind.
    ///
    /// - Returns: The file, or `nil` if there isn't one.
    func open() throws -> VaultSlotFile? {
        try withLock { file in
            file.removeStrayTemporaryFiles()
            return try file.read()
        }
    }

    /// Runs `body` holding the lock, so no other writer changes the file meanwhile.
    ///
    /// Waiting for the lock blocks the calling thread, briefly: another writer only holds it while it replaces the
    /// file.
    func withLock<Result>(_ body: (Locked) throws -> Result) throws -> Result {
        let lock = try fileSystem.lock(lockURL)
        defer { fileSystem.unlock(lock) }
        return try body(Locked(file: self))
    }
}

extension EncryptedVaultFile {
    /// The file while its lock is held. Use it only inside `withLock(_:)`.
    struct Locked {
        let file: EncryptedVaultFile

        /// The file as it is now, or `nil` if there isn't one.
        func read() throws -> VaultSlotFile? {
            try file.fileSystem.contents(of: file.url).map { try VaultSlotFile(bytes: $0) }
        }

        /// Replaces the file with `newFile`, through a temp file that's flushed, read back and verified first.
        ///
        /// - Parameter verify: Checks the file as it was read back, before it replaces the old one. It throws if the
        ///   file doesn't hold what the writer meant it to.
        /// - Throws: If any step before the rename fails, leaving the old file as it was and no temp file.
        func write(_ newFile: VaultSlotFile, verify: (VaultSlotFile) throws -> Void) throws {
            let fileSystem = file.fileSystem
            let temporaryURL = file.directory.appending(path: temporaryFilePrefix + UUID().uuidString)
            do {
                try fileSystem.createFile(at: temporaryURL, contents: newFile.bytes)
                try fileSystem.synchronizeFile(at: temporaryURL)
                guard let written = try fileSystem.contents(of: temporaryURL), written == newFile.bytes else {
                    throw EncryptedVaultStoreError.verificationFailed
                }
                try verify(VaultSlotFile(bytes: written))
                try fileSystem.moveItem(at: temporaryURL, replacing: file.url)
            } catch {
                try? fileSystem.removeItem(at: temporaryURL)
                throw error
            }
            // The rename is the commit point: from here the file holds the new contents, so failing to flush the
            // directory doesn't undo the change. APFS renames atomically either way; flushing only makes it survive a
            // power loss straight away.
            try? fileSystem.synchronizeDirectory(at: file.directory)
        }

        /// Removes temp files left by a writer that crashed before its rename, as far as it can.
        ///
        /// They're safe to remove while the lock is held, because a writer holds it until its temp file is renamed
        /// or removed. Each is an old copy of the whole file, so leaving it would show which slots changed since.
        func removeStrayTemporaryFiles() {
            let contents = (try? file.fileSystem.contentsOfDirectory(at: file.directory)) ?? []
            for url in contents where url.lastPathComponent.hasPrefix(temporaryFilePrefix) {
                try? file.fileSystem.removeItem(at: url)
            }
        }
    }
}
