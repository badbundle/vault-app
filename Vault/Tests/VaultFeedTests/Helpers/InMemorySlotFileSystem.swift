import Foundation
import FoundationExtensions
@testable import VaultFeed

/// A file system in memory, for tests that don't need a real disk.
///
/// Locks behave like `flock`: one holder at a time. It keeps each file's protection, and while the device is
/// locked (`isDeviceLocked`), reading a file with complete protection fails, as it does on a device.
final class InMemorySlotFileSystem: SlotFileSystem {
    private struct State {
        var files = [String: Data]()
        var protections = [String: SlotFileProtection]()
        var heldLocks = Set<String>()
        var lastDescriptor: Int32 = 0
        var isDeviceLocked = false
    }

    private let state = SharedMutex(State())

    func tryLock(_ url: URL) throws -> SlotFileLock? {
        state.modify { state in
            guard !state.heldLocks.contains(url.path) else { return nil }
            state.heldLocks.insert(url.path)
            state.files[url.path] = state.files[url.path] ?? Data()
            state.lastDescriptor += 1
            return SlotFileLock(url: url, descriptor: state.lastDescriptor)
        }
    }

    func unlock(_ lock: SlotFileLock) {
        state.modify { _ = $0.heldLocks.remove(lock.url.path) }
    }

    /// Whether the device is locked, so files with complete protection can't be read.
    var isDeviceLocked: Bool {
        get { state.get { $0.isDeviceLocked } }
        set { state.modify { $0.isDeviceLocked = newValue } }
    }

    /// The protection the file was created with, or `nil` if there's no file or it was put there directly.
    func protection(of url: URL) -> SlotFileProtection? {
        state.get { $0.protections[url.path] }
    }

    func contents(of url: URL) throws -> Data? {
        try state.get { state in
            if state.isDeviceLocked, state.protections[url.path] == .complete {
                throw CocoaError(.fileReadNoPermission)
            }
            return state.files[url.path]
        }
    }

    func prefix(of url: URL, length: Int) throws -> (bytes: Data, fileSize: Int)? {
        try contents(of: url).map { (Data($0.prefix(length)), $0.count) }
    }

    func fileSize(of url: URL) throws -> Int? {
        state.get { $0.files[url.path]?.count }
    }

    func createFile(at url: URL, contents: Data, protection: SlotFileProtection) throws {
        try state.modify { state in
            guard state.files[url.path] == nil else { throw POSIXError(.EEXIST) }
            state.files[url.path] = contents
            state.protections[url.path] = protection
        }
    }

    func synchronizeFile(at url: URL) throws {
        guard try contents(of: url) != nil else { throw POSIXError(.ENOENT) }
    }

    func moveItem(at source: URL, replacing destination: URL) throws {
        try state.modify { state in
            guard let data = state.files.removeValue(forKey: source.path) else { throw POSIXError(.ENOENT) }
            state.files[destination.path] = data
            state.protections[destination.path] = state.protections.removeValue(forKey: source.path)
        }
    }

    func synchronizeDirectory(at _: URL) throws {}

    /// Removes the file, and any file under it as a directory.
    func removeItem(at url: URL) throws {
        state.modify { state in
            let isRemoved = { (path: String) in path == url.path || path.hasPrefix(url.path + "/") }
            state.files = state.files.filter { path, _ in !isRemoved(path) }
            state.protections = state.protections.filter { path, _ in !isRemoved(path) }
        }
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        state.get { state in
            state.files.keys
                .map { URL(filePath: $0) }
                .filter { $0.deletingLastPathComponent().path == url.path }
        }
    }

    /// Replaces a file's contents directly, or deletes it, as another process might.
    func setContents(_ data: Data?, at url: URL) {
        state.modify { state in
            state.files[url.path] = data
            state.protections[url.path] = nil
        }
    }
}
