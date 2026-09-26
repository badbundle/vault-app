import Foundation

/// The file operations that read and replace the encrypted vault file.
///
/// Each one is a step `EncryptedVaultFile` can fail at. Tests inject file systems that fail or stop at any step, to
/// check that no failure loses data.
protocol SlotFileSystem: Sendable {
    /// Takes an exclusive lock on the file at `url`, creating the file if it isn't there, or returns `nil` straight
    /// away if anyone else, in this process or another, holds it.
    func tryLock(_ url: URL) throws -> SlotFileLock?
    /// Releases a lock. It can't fail: closing the file releases the lock, as a crash would.
    func unlock(_ lock: SlotFileLock)
    /// The file's contents, or `nil` if there's no file.
    func contents(of url: URL) throws -> Data?
    /// Creates a file with these contents, readable only while the device is unlocked. Fails if the file exists.
    func createFile(at url: URL, contents: Data) throws
    /// Flushes the file to permanent storage, including the drive's own cache (`F_FULLFSYNC`).
    func synchronizeFile(at url: URL) throws
    /// Renames `source` to `destination` in one step, replacing the file there.
    func moveItem(at source: URL, replacing destination: URL) throws
    /// Flushes the directory to permanent storage, so a rename in it survives a power loss.
    func synchronizeDirectory(at url: URL) throws
    /// Deletes the file.
    func removeItem(at url: URL) throws
    /// Every file in the directory.
    func contentsOfDirectory(at url: URL) throws -> [URL]
}

/// A lock taken with `SlotFileSystem.tryLock(_:)`.
struct SlotFileLock: Sendable {
    /// The lock file.
    let url: URL
    /// The open lock file, which holds the lock until it's closed.
    let descriptor: Int32
}

/// The device's file system.
struct LiveSlotFileSystem: SlotFileSystem {
    func tryLock(_ url: URL) throws -> SlotFileLock? {
        let descriptor = try Self.open(url, flags: O_RDWR | O_CREAT)
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            let error = errno
            if error == EINTR {
                continue
            }
            close(descriptor)
            if error == EWOULDBLOCK {
                return nil
            }
            throw POSIXError(Self.code(error))
        }
        return SlotFileLock(url: url, descriptor: descriptor)
    }

    func unlock(_ lock: SlotFileLock) {
        close(lock.descriptor)
    }

    func contents(of url: URL) throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    func createFile(at url: URL, contents: Data) throws {
        try contents.write(to: url, options: [.withoutOverwriting, .completeFileProtection])
    }

    func synchronizeFile(at url: URL) throws {
        let descriptor = try Self.open(url, flags: O_RDWR)
        defer { close(descriptor) }
        try Self.fullSynchronize(descriptor)
    }

    func moveItem(at source: URL, replacing destination: URL) throws {
        guard rename(source.path, destination.path) == 0 else { throw POSIXError(Self.code(errno)) }
    }

    func synchronizeDirectory(at url: URL) throws {
        let descriptor = try Self.open(url, flags: O_RDONLY | O_DIRECTORY)
        defer { close(descriptor) }
        try Self.fullSynchronize(descriptor)
    }

    func removeItem(at url: URL) throws {
        guard unlink(url.path) == 0 else { throw POSIXError(Self.code(errno)) }
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
    }

    /// `F_FULLFSYNC`, which flushes the drive's own cache too: on Darwin, plain `fsync` doesn't. Some file systems
    /// can't do it. APFS can, but fall back to `fsync` as SQLite does.
    private static func fullSynchronize(_ descriptor: Int32) throws {
        guard fcntl(descriptor, F_FULLFSYNC) == -1 else { return }
        guard fsync(descriptor) == 0 else { throw POSIXError(code(errno)) }
    }

    private static func open(_ url: URL, flags: Int32) throws -> Int32 {
        let descriptor = Darwin.open(url.path, flags | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(code(errno)) }
        return descriptor
    }

    private static func code(_ error: Int32) -> POSIXErrorCode {
        POSIXErrorCode(rawValue: error) ?? .EIO
    }
}
