import Foundation
import Testing
@testable import VaultFeed

struct EncryptedVaultFileTests {
    private struct VerifyError: Error {}

    // MARK: Replacing the file

    @Test
    func write_replacesTheFileThroughAFlushedAndVerifiedTempFile() throws {
        let fixture = try EncryptedVaultFixture()
        let fileSystem = FaultInjectingSlotFileSystem(wrapping: fixture.file.fileSystem)
        let file = fixture.through(fileSystem).file
        let newFile = try VaultSlotFile(kdfParameters: EncryptedVaultFixture.kdfParameters)
        var verified: VaultSlotFile?

        try file.withLock { file in
            try file.write(newFile) { verified = $0 }
        }

        #expect(verified == newFile)
        #expect(try fixture.bytes() == newFile.bytes)
        #expect(try fixture.temporaryFileNames().isEmpty)
        #expect(fileSystem.log == [
            "lock vault-slots.lock",
            "create temp",
            "flush temp",
            "read temp",
            "rename temp to vault-slots.v1",
            "flush directory",
            "unlock",
        ])
    }

    @Test
    func write_thatFailsVerification_leavesTheOldFileAndNoTempFile() throws {
        let fixture = try EncryptedVaultFixture()
        let bytesBefore = try fixture.bytes()
        let newFile = try VaultSlotFile(kdfParameters: EncryptedVaultFixture.kdfParameters)

        #expect(throws: VerifyError.self) {
            try fixture.file.withLock { file in
                try file.write(newFile) { _ in throw VerifyError() }
            }
        }

        #expect(try fixture.bytes() == bytesBefore)
        #expect(try fixture.temporaryFileNames().isEmpty)
    }

    @Test
    func open_removesOnlyTemporaryFiles() throws {
        let fileSystem = InMemorySlotFileSystem()
        let fixture = try EncryptedVaultFixture(fileSystem: fileSystem)
        let directory = fixture.file.directory
        let other = directory.appending(path: "vault-storage-state.json")
        try fileSystem.createFile(at: other, contents: Data("{}".utf8))
        for name in ["a", "b"] {
            try fileSystem.createFile(
                at: directory.appending(path: EncryptedVaultFile.temporaryFilePrefix + name),
                contents: Data(),
            )
        }

        let opened = try fixture.file.open()

        #expect(try opened?.bytes == fixture.bytes())
        let names = try Set(fileSystem.contentsOfDirectory(at: directory).map(\.lastPathComponent))
        #expect(names == [EncryptedVaultFile.fileName, EncryptedVaultFile.lockFileName, "vault-storage-state.json"])
    }
}

// MARK: - The device's file system

extension EncryptedVaultFileTests {
    @Test
    func live_readsWritesRenamesAndRemovesFiles() async throws {
        try await withTemporaryDirectory { directory in
            let fileSystem = LiveSlotFileSystem()
            let source = directory.appending(path: "source")
            let destination = directory.appending(path: "destination")
            try fileSystem.createFile(at: destination, contents: Data("old".utf8))

            try fileSystem.createFile(at: source, contents: Data("new".utf8))
            try fileSystem.synchronizeFile(at: source)
            try fileSystem.moveItem(at: source, replacing: destination)
            try fileSystem.synchronizeDirectory(at: directory)

            #expect(try fileSystem.contents(of: destination) == Data("new".utf8))
            #expect(try fileSystem.contents(of: source) == nil)
            #expect(try fileSystem.contentsOfDirectory(at: directory).map(\.lastPathComponent) == ["destination"])
            try fileSystem.removeItem(at: destination)
            #expect(try fileSystem.contents(of: destination) == nil)
        }
    }

    @Test
    func live_createFileRefusesToReplaceAFile() async throws {
        try await withTemporaryDirectory { directory in
            let fileSystem = LiveSlotFileSystem()
            let url = directory.appending(path: "file")
            try fileSystem.createFile(at: url, contents: Data("first".utf8))

            #expect(throws: (any Error).self) {
                try fileSystem.createFile(at: url, contents: Data("second".utf8))
            }
            #expect(try fileSystem.contents(of: url) == Data("first".utf8))
        }
    }

    /// `flock` locks belong to an open file, so two opens in one process exclude each other as two processes do.
    @Test
    func live_lockGivesUpWhileAnotherHolderKeepsIt() async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appending(path: EncryptedVaultFile.lockFileName)
            let holder = LiveSlotFileSystem()
            let waiter = LiveSlotFileSystem(lockTimeout: .milliseconds(100))
            let held = try holder.lock(url)

            let start = ContinuousClock.now
            #expect(throws: POSIXError(.EWOULDBLOCK)) {
                try waiter.lock(url)
            }
            #expect(ContinuousClock.now - start >= .milliseconds(100))

            holder.unlock(held)
            try waiter.unlock(waiter.lock(url))
        }
    }

    @Test
    func live_lockWaitsForTheHolderToLetGo() async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appending(path: EncryptedVaultFile.lockFileName)
            let fileSystem = LiveSlotFileSystem()
            let held = try fileSystem.lock(url)

            let waiting = Task.detached {
                let lock = try fileSystem.lock(url)
                let taken = ContinuousClock.now
                fileSystem.unlock(lock)
                return taken
            }
            try await Task.sleep(for: .milliseconds(50))
            let released = ContinuousClock.now
            fileSystem.unlock(held)

            #expect(try await waiting.value >= released)
        }
    }
}
