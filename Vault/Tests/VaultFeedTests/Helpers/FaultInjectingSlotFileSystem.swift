import Foundation
import FoundationExtensions
@testable import VaultFeed

/// Wraps a file system, logs everything done through it, and can make a step go wrong.
///
/// Every operation but `unlock(_:)` is a step. Steps are numbered from 1, counting from when the fault was injected.
final class FaultInjectingSlotFileSystem: SlotFileSystem {
    enum Fault: Equatable, Sendable {
        /// Those steps throw, and everything else works.
        case fail(atSteps: Set<Int>)
        /// The process "crashes" at that step: it and every later step throw, so nothing after it happens, including
        /// the clean-up a failure would do. Locks are still released, as the system releases a dead process's locks.
        case crash(atStep: Int)
        /// Reading back a temp file gives different bytes from the ones written.
        case corruptReadBack
        /// One step fails, and then the process "crashes" at a later one, as `crash(atStep:)` does.
        case failThenCrash(failAtStep: Int, crashAtStep: Int)

        /// That step throws, and everything else works.
        static func fail(atStep step: Int) -> Fault {
            .fail(atSteps: [step])
        }
    }

    struct InjectedFault: Error {}

    private struct State {
        var log = [String]()
        var fault: Fault?
        var stepsSinceInjecting = 0
    }

    private let base: any SlotFileSystem
    private let state = SharedMutex(State())

    init(wrapping base: any SlotFileSystem) {
        self.base = base
    }

    /// Everything done so far, in order, naming the file each step was taken on (a temp file is `temp`).
    var log: [String] {
        state.get { $0.log }
    }

    /// Makes a step go wrong from now on, counting steps afresh. `nil` stops injecting.
    func inject(_ fault: Fault?) {
        state.modify { state in
            state.fault = fault
            state.stepsSinceInjecting = 0
        }
    }

    func tryLock(_ url: URL) throws -> SlotFileLock? {
        try step("lock \(Self.name(url))")
        return try base.tryLock(url)
    }

    func unlock(_ lock: SlotFileLock) {
        state.modify { $0.log.append("unlock") }
        base.unlock(lock)
    }

    func contents(of url: URL) throws -> Data? {
        try step("read \(Self.name(url))")
        guard var data = try base.contents(of: url) else { return nil }
        if state.get({ $0.fault }) == .corruptReadBack, Self.isTemporary(url) {
            data[data.startIndex + data.count / 2] ^= 0x01
        }
        return data
    }

    func prefix(of url: URL, length: Int) throws -> (bytes: Data, fileSize: Int)? {
        try step("read the start of \(Self.name(url))")
        return try base.prefix(of: url, length: length)
    }

    func fileSize(of url: URL) throws -> Int? {
        try step("size of \(Self.name(url))")
        return try base.fileSize(of: url)
    }

    func createFile(at url: URL, contents: Data, protection: SlotFileProtection) throws {
        try step("create \(Self.name(url))")
        try base.createFile(at: url, contents: contents, protection: protection)
    }

    func synchronizeFile(at url: URL) throws {
        try step("flush \(Self.name(url))")
        try base.synchronizeFile(at: url)
    }

    func moveItem(at source: URL, replacing destination: URL) throws {
        try step("rename \(Self.name(source)) to \(Self.name(destination))")
        try base.moveItem(at: source, replacing: destination)
    }

    func synchronizeDirectory(at url: URL) throws {
        try step("flush directory")
        try base.synchronizeDirectory(at: url)
    }

    func removeItem(at url: URL) throws {
        try step("remove \(Self.name(url))")
        try base.removeItem(at: url)
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        try step("list directory")
        return try base.contentsOfDirectory(at: url)
    }

    /// Logs the step, then throws if it's the one to go wrong.
    private func step(_ name: String) throws {
        let (number, fault) = state.modify { state in
            state.log.append(name)
            state.stepsSinceInjecting += 1
            return (state.stepsSinceInjecting, state.fault)
        }
        switch fault {
        case let .fail(atSteps) where atSteps.contains(number):
            throw InjectedFault()
        case let .crash(atStep) where number >= atStep:
            throw InjectedFault()
        case let .failThenCrash(failAtStep, crashAtStep) where number == failAtStep || number >= crashAtStep:
            throw InjectedFault()
        default:
            break
        }
    }

    private static func isTemporary(_ url: URL) -> Bool {
        url.lastPathComponent.hasPrefix(EncryptedVaultFile.temporaryFilePrefix)
    }

    private static func name(_ url: URL) -> String {
        if isTemporary(url) {
            "temp"
        } else if url.lastPathComponent.hasPrefix(VaultStorageStateFile.temporaryFilePrefix) {
            "state temp"
        } else if url.lastPathComponent.hasPrefix(PersistedLocalVaultStoreArchives.directoryNamePrefix) {
            "archive"
        } else {
            url.lastPathComponent
        }
    }
}
