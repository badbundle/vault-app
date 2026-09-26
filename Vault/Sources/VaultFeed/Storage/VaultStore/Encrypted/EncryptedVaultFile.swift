import Foundation

/// The encrypted vault file, `vault-slots.v1`, and how it's read and replaced.
///
/// Every writer, in the app or an extension, holds `vault-slots.lock` with `flock` while it reads and replaces the
/// file, so they take turns. A replacement never overwrites the only copy of anything:
///
/// 1. Temp files an earlier writer left behind, by crashing before its rename, are removed.
/// 2. The new file is written to a temp file, `.vault-slots.tmp-<random>`, and flushed with `F_FULLFSYNC`.
/// 3. It's read back and verified: it must match what was written byte for byte, and the writer checks that its
///    slot opens to what it saved. The read most likely comes from the page cache, so this proves the sealing and
///    encoding round-trip, not what reached storage.
/// 4. It's renamed over `vault-slots.v1`, which replaces every slot in one step. Then the directory is flushed.
///
/// A failure before the rename removes the temp file and leaves the old file as it was. A crash before the rename
/// leaves a temp file behind, which the next write, or `open()`, removes. Each is an old copy of the whole file, so
/// it could hold items deleted since (MANIFESTO C6). See "Crash safety" in `docs/on-device-encryption.md`.
struct EncryptedVaultFile: Sendable {
    static let fileName = "vault-slots.v1"
    static let lockFileName = "vault-slots.lock"
    static let temporaryFilePrefix = ".vault-slots.tmp-"
    /// How often `withLock(_:)` tries the lock while another writer holds it.
    static let lockRetryInterval = Duration.milliseconds(2)

    /// The directory the file is in.
    let directory: URL
    let fileSystem: any SlotFileSystem
    /// How long `withLock(_:)` waits for another writer before giving up with `EWOULDBLOCK`.
    ///
    /// A save holds the lock for tens of milliseconds, so waiting this long means something is wrong, and a store
    /// that waited forever would never finish its change or let the vault lock.
    let lockTimeout: Duration

    init(
        directory: URL,
        fileSystem: any SlotFileSystem = LiveSlotFileSystem(),
        lockTimeout: Duration = .seconds(10),
    ) {
        self.directory = directory
        self.fileSystem = fileSystem
        self.lockTimeout = lockTimeout
    }

    var url: URL {
        directory.appending(path: Self.fileName)
    }

    var lockURL: URL {
        directory.appending(path: Self.lockFileName)
    }

    /// Reads the file to unlock a vault from it, first removing any temp files a crash left behind, as far as it
    /// can. (A write removes them too, and fails if it can't.)
    ///
    /// - Returns: The file, or `nil` if there isn't one.
    func open() async throws -> VaultSlotFile? {
        try await withLock { file in
            try? file.removeStrayTemporaryFiles()
            return try file.read()
        }
    }

    /// Runs `body` holding the lock, so no other writer changes the file meanwhile.
    ///
    /// While another writer holds the lock, it tries again every couple of milliseconds, without blocking a thread,
    /// for up to `lockTimeout`.
    func withLock<Result>(_ body: (Locked) throws -> Result) async throws -> Result {
        let lock = try await acquireLock()
        defer { fileSystem.unlock(lock) }
        return try body(Locked(file: self))
    }

    private func acquireLock() async throws -> SlotFileLock {
        let deadline = ContinuousClock.now + lockTimeout
        while true {
            if let lock = try fileSystem.tryLock(lockURL) {
                return lock
            }
            guard ContinuousClock.now < deadline else { throw POSIXError(.EWOULDBLOCK) }
            try await Task.sleep(for: Self.lockRetryInterval)
        }
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
        /// - Throws: If temp files left behind by a crash can't be removed, or if any step before the rename fails.
        ///   The old file stays as it was, and this write leaves no temp file, unless removing it fails too.
        func write(_ newFile: VaultSlotFile, verify: (VaultSlotFile) throws -> Void) throws {
            try removeStrayTemporaryFiles()
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

        /// Removes temp files left by a writer that crashed before its rename, or whose removal failed.
        ///
        /// They're safe to remove while the lock is held, because a writer holds it until its temp file is renamed
        /// or removed. Each is an old copy of the whole file: it could hold items deleted since, under the same keys,
        /// and it would show which slots changed since.
        func removeStrayTemporaryFiles() throws {
            let contents = try file.fileSystem.contentsOfDirectory(at: file.directory)
            for url in contents where url.lastPathComponent.hasPrefix(temporaryFilePrefix) {
                try file.fileSystem.removeItem(at: url)
            }
        }
    }
}
