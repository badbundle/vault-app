import Foundation
import FoundationExtensions
import Testing
@testable import VaultFeed

/// Recovering at launch from each state the journal can be in, and reading the state from an extension.
struct VaultStorageRecoveryTests {
    @Test
    func recover_withNoStateFile_isPlainAndTouchesNothing() async throws {
        try await withTemporaryDirectory { directory in
            try Self.makePlainStore(in: directory)
            let before = try Self.fileNames(in: directory)

            #expect(try VaultStorageRecovery(directory: directory).recoverAtLaunch() == .plain)

            #expect(try Self.fileNames(in: directory) == before)
        }
    }

    /// The app stopped mid-conversion: the plain store is still the vault.
    @Test
    func recover_whileEncrypting_deletesTheEncryptedFilesAndGoesBackToPlain() async throws {
        try await withTemporaryDirectory { directory in
            try Self.makePlainStore(in: directory)
            try Self.makeEncryptedFiles(in: directory)
            try Self.write(VaultStorageState(mode: .plain, transition: .encrypting), in: directory)

            #expect(try VaultStorageRecovery(directory: directory).recoverAtLaunch() == .plain)

            #expect(try Self.fileNames(in: directory) == Self.plainStoreNames)
        }
    }

    @Test
    func recover_plainWithAStrayEncryptedFile_deletesIt() async throws {
        try await withTemporaryDirectory { directory in
            try Self.makePlainStore(in: directory)
            try Self.makeEncryptedFiles(in: directory)

            #expect(try VaultStorageRecovery(directory: directory).recoverAtLaunch() == .plain)

            #expect(try Self.fileNames(in: directory) == Self.plainStoreNames)
        }
    }

    /// Something has gone badly wrong, such as a lost state file. The encrypted file might be the only copy of the
    /// vault, so it stays.
    @Test
    func recover_plainWithAnEncryptedFileButNoPlainStore_deletesNothing() async throws {
        try await withTemporaryDirectory { directory in
            try Self.makeEncryptedFiles(in: directory)
            let before = try Self.fileNames(in: directory)

            #expect(throws: VaultStorageRecovery.Failure.encryptedFileWithoutPlainStore) {
                try VaultStorageRecovery(directory: directory).recoverAtLaunch()
            }

            #expect(try Self.fileNames(in: directory) == before)
        }
    }

    /// The conversion committed, and the app stopped while deleting the plain store.
    @Test
    func recover_whileDeletingThePlainStore_finishesAndKeepsTheDeadline() async throws {
        try await withTemporaryDirectory { directory in
            try Self.makePlainStore(in: directory)
            try PendingKillphraseRehashStore(
                fileURL: PendingKillphraseRehashStore.defaultURL(storeDirectory: directory),
            ).write([])
            let confirmed = try VaultEncryptionConverterTests.makeArchive(in: directory)
            let unconfirmed = directory.appending(path: PersistedLocalVaultStoreArchives.directoryNamePrefix + "later")
            try FileManager.default.createDirectory(at: unconfirmed, withIntermediateDirectories: true)
            try Self.makeEncryptedFiles(in: directory, temporary: false)
            try Self.write(
                VaultStorageState(
                    mode: .password,
                    transition: .deletingPlainStore(archives: [confirmed.lastPathComponent]),
                    unlockDeadline: .seconds(1),
                ),
                in: directory,
            )

            #expect(try VaultStorageRecovery(directory: directory).recoverAtLaunch() == .password)
            // Safe to run again.
            #expect(try VaultStorageRecovery(directory: directory).recoverAtLaunch() == .password)

            #expect(try Self.fileNames(in: directory) == [
                EncryptedVaultFile.fileName,
                VaultStorageStateFile.fileName,
                unconfirmed.lastPathComponent,
            ])
            // The system surfaces are still to be cleared.
            #expect(try Self.read(in: directory) == VaultStorageState(
                mode: .password,
                transition: .clearingSystemSurfaces,
                unlockDeadline: .seconds(1),
            ))
        }
    }

    /// Something has gone badly wrong, such as a lost encrypted file. The plain store might be the only copy of the
    /// vault, so it stays.
    @Test(arguments: [nil, Data("not a vault file".utf8)])
    func recover_whileDeletingThePlainStoreWithoutAnEncryptedFile_deletesNothing(encryptedFile: Data?) async throws {
        try await withTemporaryDirectory { directory in
            try Self.makePlainStore(in: directory)
            try encryptedFile?.write(to: directory.appending(path: EncryptedVaultFile.fileName))
            try Self.write(
                VaultStorageState(
                    mode: .password,
                    transition: .deletingPlainStore(archives: []),
                    unlockDeadline: .seconds(1),
                ),
                in: directory,
            )
            let before = try Self.fileNames(in: directory)

            #expect(throws: VaultStorageRecovery.Failure.plainStoreWithoutEncryptedFile) {
                try VaultStorageRecovery(directory: directory).recoverAtLaunch()
            }

            #expect(try Self.fileNames(in: directory) == before)
        }
    }

    /// The app stopped after deleting the plain store, before clearing QuickType and the widgets.
    @Test
    func finishClearingSystemSurfaces_clearsThemOnceThenClearsTheJournal() async throws {
        try await withTemporaryDirectory { directory in
            try Self.write(
                VaultStorageState(mode: .password, transition: .clearingSystemSurfaces, unlockDeadline: .seconds(1)),
                in: directory,
            )
            let clears = SharedMutex(0)
            let recovery = VaultStorageRecovery(directory: directory)

            try await recovery.finishClearingSystemSurfaces { clears.modify { $0 += 1 } }
            try await recovery.finishClearingSystemSurfaces { clears.modify { $0 += 1 } }

            #expect(clears.value == 1)
            #expect(try Self.read(in: directory) == VaultStorageState(mode: .password, unlockDeadline: .seconds(1)))
        }
    }

    @Test
    func recover_encrypted_touchesNothingButStrayStateTempFiles() async throws {
        try await withTemporaryDirectory { directory in
            try Self.makeEncryptedFiles(in: directory, temporary: false)
            try Self.write(VaultStorageState(mode: .password, unlockDeadline: .seconds(1)), in: directory)
            let before = try Self.fileNames(in: directory)
            try Data().write(to: directory.appending(path: VaultStorageStateFile.temporaryFilePrefix + "stray"))

            #expect(try VaultStorageRecovery(directory: directory).recoverAtLaunch() == .password)

            #expect(try Self.fileNames(in: directory) == before)
        }
    }
}

// MARK: - The state file

extension VaultStorageRecoveryTests {
    @Test
    func stateFile_readsBackWhatItWrote_andGoingBackToPlainRemovesIt() async throws {
        try await withTemporaryDirectory { directory in
            let file = VaultStorageStateFile(directory: directory)
            let states = [
                VaultStorageState(mode: .plain, transition: .encrypting),
                VaultStorageState(
                    mode: .password,
                    transition: .deletingPlainStore(archives: ["a", "b"]),
                    unlockDeadline: .milliseconds(750),
                ),
                VaultStorageState(mode: .password, unlockDeadline: .milliseconds(750)),
            ]

            for state in states {
                try file.write(state)
                #expect(try file.read() == state)
            }
            try file.write(.plain)

            #expect(try Self.fileNames(in: directory).isEmpty)
            #expect(try file.read() == .plain)
        }
    }

    @Test
    func stateFile_asTheDeadlineStore_onlyEverRaisesTheDeadline() async throws {
        try await withTemporaryDirectory { directory in
            let file = VaultStorageStateFile(directory: directory)
            try file.write(VaultStorageState(mode: .password, unlockDeadline: .seconds(1)))

            try await file.raiseUnlockDeadline(to: .milliseconds(500))
            #expect(try await file.unlockDeadline() == .seconds(1))
            try await file.raiseUnlockDeadline(to: .seconds(2))
            #expect(try await file.unlockDeadline() == .seconds(2))
            #expect(try file.read().mode == .password)
        }
    }

    @Test
    func isPlain_forAnExtension_onlyWhenThereIsNothingElseItCouldBe() async throws {
        try await withTemporaryDirectory { directory in
            #expect(VaultStorageState.isPlain(inDirectory: directory))

            for state in [
                VaultStorageState(mode: .plain, transition: .encrypting),
                VaultStorageState(mode: .password, transition: .deletingPlainStore(archives: [])),
                VaultStorageState(mode: .password),
            ] {
                try Self.write(state, in: directory)
                #expect(!VaultStorageState.isPlain(inDirectory: directory), "\(state)")
            }

            try Data("not json".utf8).write(to: directory.appending(path: VaultStorageStateFile.fileName))
            #expect(!VaultStorageState.isPlain(inDirectory: directory))
        }
    }
}

// MARK: - Helpers

extension VaultStorageRecoveryTests {
    static let plainStoreNames: Set<String> = [
        "vault-primary.sqlite",
        "vault-primary.sqlite-wal",
        "vault-primary.sqlite-shm",
    ]

    /// Stand-ins for the plain store's files: recovery only looks at their names.
    static func makePlainStore(in directory: URL) throws {
        for name in plainStoreNames {
            try Data("plain".utf8).write(to: directory.appending(path: name))
        }
    }

    /// A real encrypted file, with every slot random, and a temp file beside it.
    static func makeEncryptedFiles(in directory: URL, temporary: Bool = true) throws {
        try VaultSlotFile(kdfParameters: EncryptedVaultFixture.kdfParameters).bytes
            .write(to: directory.appending(path: EncryptedVaultFile.fileName))
        if temporary {
            try Data("encrypted".utf8)
                .write(to: directory.appending(path: EncryptedVaultFile.temporaryFilePrefix + "a"))
        }
    }

    static func write(_ state: VaultStorageState, in directory: URL) throws {
        try VaultStorageStateFile(directory: directory).write(state)
    }

    static func read(in directory: URL) throws -> VaultStorageState {
        try VaultStorageStateFile(directory: directory).read()
    }

    static func fileNames(in directory: URL) throws -> Set<String> {
        try Set(FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)))
    }
}
