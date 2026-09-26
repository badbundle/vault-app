import Foundation
import FoundationExtensions
@testable import VaultFeed

/// A file system in memory, for tests that don't need a real disk.
///
/// Locks behave like `flock`: one holder at a time.
final class InMemorySlotFileSystem: SlotFileSystem {
    private struct State {
        var files = [String: Data]()
        var heldLocks = Set<String>()
        var lastDescriptor: Int32 = 0
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

    func contents(of url: URL) throws -> Data? {
        state.get { $0.files[url.path] }
    }

    func createFile(at url: URL, contents: Data) throws {
        try state.modify { state in
            guard state.files[url.path] == nil else { throw POSIXError(.EEXIST) }
            state.files[url.path] = contents
        }
    }

    func synchronizeFile(at url: URL) throws {
        guard try contents(of: url) != nil else { throw POSIXError(.ENOENT) }
    }

    func moveItem(at source: URL, replacing destination: URL) throws {
        try state.modify { state in
            guard let data = state.files.removeValue(forKey: source.path) else { throw POSIXError(.ENOENT) }
            state.files[destination.path] = data
        }
    }

    func synchronizeDirectory(at _: URL) throws {}

    func removeItem(at url: URL) throws {
        try state.modify { state in
            guard state.files.removeValue(forKey: url.path) != nil else { throw POSIXError(.ENOENT) }
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
        state.modify { $0.files[url.path] = data }
    }
}
