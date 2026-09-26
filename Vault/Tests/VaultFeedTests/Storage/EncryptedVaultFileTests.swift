import Foundation
import Testing
@testable import VaultFeed

struct EncryptedVaultFileTests {
    private struct VerifyError: Error {}

    // MARK: Replacing the file

    @Test
    func write_replacesTheFileThroughAFlushedAndVerifiedTempFile() async throws {
        let fixture = try EncryptedVaultFixture()
        let fileSystem = FaultInjectingSlotFileSystem(wrapping: fixture.file.fileSystem)
        let file = fixture.through(fileSystem).file
        let newFile = try VaultSlotFile(kdfParameters: EncryptedVaultFixture.kdfParameters)
        var verified: VaultSlotFile?

        try await file.withLock { file in
            try file.write(newFile) { verified = $0 }
        }

        #expect(verified == newFile)
        #expect(try fixture.bytes() == newFile.bytes)
        #expect(try fixture.temporaryFileNames().isEmpty)
        #expect(fileSystem.log == [
            "lock vault-slots.lock",
            "list directory",
            "create temp",
            "flush temp",
            "read temp",
            "rename temp to vault-slots.v1",
            "flush directory",
            "unlock",
        ])
    }

    @Test
    func write_thatFailsVerification_leavesTheOldFileAndNoTempFile() async throws {
        let fixture = try EncryptedVaultFixture()
        let bytesBefore = try fixture.bytes()
        let newFile = try VaultSlotFile(kdfParameters: EncryptedVaultFixture.kdfParameters)

        await #expect(throws: VerifyError.self) {
            try await fixture.file.withLock { file in
                try file.write(newFile) { _ in throw VerifyError() }
            }
        }

        #expect(try fixture.bytes() == bytesBefore)
        #expect(try fixture.temporaryFileNames().isEmpty)
    }

    @Test
    func write_thatCantRemoveAStrayTempFile_writesNothing() async throws {
        let fixture = try EncryptedVaultFixture()
        let fileSystem = FaultInjectingSlotFileSystem(wrapping: fixture.file.fileSystem)
        let stray = fixture.file.directory.appending(path: EncryptedVaultFile.temporaryFilePrefix + "stray")
        try fileSystem.createFile(at: stray, contents: Data())
        let bytesBefore = try fixture.bytes()
        let newFile = try VaultSlotFile(kdfParameters: EncryptedVaultFixture.kdfParameters)

        // Counting from here: lock, list the directory, remove the stray.
        fileSystem.inject(.fail(atStep: 3))
        await #expect(throws: FaultInjectingSlotFileSystem.InjectedFault.self) {
            try await fixture.through(fileSystem).file.withLock { file in
                try file.write(newFile) { _ in }
            }
        }

        #expect(try fixture.bytes() == bytesBefore)
        #expect(try fixture.temporaryFileNames() == [stray.lastPathComponent])
    }

    @Test
    func open_removesOnlyTemporaryFiles() async throws {
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

        let opened = try await fixture.file.open()

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
    func live_tryLockFindsTheLockHeldUntilItsHolderLetsGo() async throws {
        try await withTemporaryDirectory { directory in
            let url = directory.appending(path: EncryptedVaultFile.lockFileName)
            let fileSystem = LiveSlotFileSystem()
            let held = try #require(try fileSystem.tryLock(url))

            #expect(try fileSystem.tryLock(url) == nil)

            fileSystem.unlock(held)
            let again = try #require(try fileSystem.tryLock(url))
            fileSystem.unlock(again)
        }
    }

    @Test
    func withLock_waitsForTheHolderToLetGo() async throws {
        try await withTemporaryDirectory { directory in
            let file = EncryptedVaultFile(directory: directory)
            let held = try #require(try file.fileSystem.tryLock(file.lockURL))

            let waiting = Task {
                try await file.withLock { _ in ContinuousClock.now }
            }
            try await Task.sleep(for: .milliseconds(50))
            let released = ContinuousClock.now
            file.fileSystem.unlock(held)

            #expect(try await waiting.value >= released)
        }
    }

    @Test
    func withLock_givesUpWhileAnotherHolderKeepsIt() async throws {
        try await withTemporaryDirectory { directory in
            let file = EncryptedVaultFile(directory: directory, lockTimeout: .milliseconds(100))
            let held = try #require(try file.fileSystem.tryLock(file.lockURL))
            defer { file.fileSystem.unlock(held) }

            let start = ContinuousClock.now
            await #expect(throws: POSIXError(.EWOULDBLOCK)) {
                try await file.withLock { _ in }
            }
            #expect(ContinuousClock.now - start >= .milliseconds(100))
        }
    }
}
