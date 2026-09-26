import CryptoKit
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

    /// The app can launch in the background while the device is locked, when the encrypted file can't be read. It
    /// only needs the file's size to know it's there.
    @Test
    func recover_whileDeletingThePlainStore_onALockedDevice_finishes() throws {
        let fileSystem = InMemorySlotFileSystem()
        let directory = EncryptedVaultFixture.inMemoryDirectory
        for url in PersistedLocalVaultStoreFactory.storeFileURLs(storageDirectory: directory) {
            fileSystem.setContents(Data("plain".utf8), at: url)
        }
        let encryptedFile = directory.appending(path: EncryptedVaultFile.fileName)
        try fileSystem.createFile(
            at: encryptedFile,
            contents: VaultSlotFile(kdfParameters: EncryptedVaultFixture.kdfParameters).bytes,
            protection: .complete,
        )
        let stateFile = VaultStorageStateFile(directory: directory, fileSystem: fileSystem)
        try stateFile.write(VaultStorageState(
            mode: .password,
            transition: .deletingPlainStore(archives: []),
            unlockDeadline: .seconds(1),
        ))
        fileSystem.isDeviceLocked = true
        #expect(throws: (any Error).self) { try fileSystem.contents(of: encryptedFile) }

        let mode = try VaultStorageRecovery(
            directory: directory,
            fileSystem: fileSystem,
            deviceKeyStore: InMemoryDeviceKeyStore(),
        ).recoverAtLaunch()

        #expect(mode == .password)
        #expect(try Set(fileSystem.contentsOfDirectory(at: directory).map(\.lastPathComponent)) == [
            EncryptedVaultFile.fileName,
            VaultStorageStateFile.fileName,
        ])
        #expect(try stateFile.read().transition == .clearingSystemSurfaces)
    }

    /// An unlock attempt can raise the deadline while QuickType and the widgets are being cleared. Clearing the
    /// journal afterwards mustn't put the old deadline back.
    @Test
    func finishClearingSystemSurfaces_keepsADeadlineRaisedWhileClearing() async throws {
        try await withTemporaryDirectory { directory in
            try Self.write(
                VaultStorageState(mode: .password, transition: .clearingSystemSurfaces, unlockDeadline: .seconds(1)),
                in: directory,
            )

            try await VaultStorageRecovery(directory: directory).finishClearingSystemSurfaces {
                try? await VaultStorageStateFile(directory: directory).raiseUnlockDeadline(to: .seconds(3))
            }

            #expect(try Self.read(in: directory) == VaultStorageState(mode: .password, unlockDeadline: .seconds(3)))
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

// MARK: - Turning the password off or back on

extension VaultStorageRecoveryTests {
    /// The rekey is one rename, so the slot is wrapped with either the device key or the password. Whether the
    /// device key opens it says which, whichever way the change was going.
    @Test(arguments: [VaultStorageState.Transition.turningOff, .turningOn])
    func recover_whileTurningThePasswordOffOrOn_withTheDeviceKeyOpeningTheVault_isDeviceKey(
        transition: VaultStorageState.Transition,
    ) throws {
        let deviceKey = SymmetricKey(size: .bits256)
        let sut = try TurningHarness(slotKey: .device(deviceKey), deviceKey: deviceKey, transition: transition)

        #expect(try sut.recovery.recoverAtLaunch() == .deviceKey)

        #expect(try sut.stateFile.read() == VaultStorageState(mode: .deviceKey, unlockDeadline: .seconds(1)))
        #expect(sut.deviceKeyStore.key != nil)
    }

    @Test
    func recover_whileTurningThePasswordOff_withTheSlotStillWrappedByThePassword_isPassword() throws {
        let sut = try TurningHarness(
            slotKey: .password(derivedKey: SymmetricKey(size: .bits256)),
            deviceKey: SymmetricKey(size: .bits256),
            transition: .turningOff,
        )

        #expect(try sut.recovery.recoverAtLaunch() == .password)

        #expect(try sut.stateFile.read() == VaultStorageState(mode: .password, unlockDeadline: .seconds(1)))
    }

    /// The password is back on, so the device key opens nothing now, and goes.
    @Test(arguments: [true, false])
    func recover_whileTurningThePasswordOn_withTheSlotWrappedByThePassword_isPasswordWithoutADeviceKey(
        hasDeviceKey: Bool,
    ) throws {
        let sut = try TurningHarness(
            slotKey: .password(derivedKey: SymmetricKey(size: .bits256)),
            deviceKey: hasDeviceKey ? SymmetricKey(size: .bits256) : nil,
            transition: .turningOn,
        )

        #expect(try sut.recovery.recoverAtLaunch() == .password)

        #expect(try sut.stateFile.read() == VaultStorageState(mode: .password, unlockDeadline: .seconds(1)))
        #expect(sut.deviceKeyStore.key == nil)
    }

    @Test
    func recover_whileTurningThePasswordOff_withoutAnEncryptedFile_changesNothing() throws {
        let sut = try TurningHarness(
            slotKey: .password(derivedKey: SymmetricKey(size: .bits256)),
            deviceKey: SymmetricKey(size: .bits256),
            transition: .turningOff,
        )
        try sut.fileSystem.removeItem(at: sut.encryptedFileURL)
        let before = try sut.stateFile.read()

        #expect(throws: VaultStorageRecovery.Failure.encryptedFileMissing) {
            try sut.recovery.recoverAtLaunch()
        }

        #expect(try sut.stateFile.read() == before)
    }

    @Test
    func recover_deviceKeyMode_touchesNothing() throws {
        let deviceKey = SymmetricKey(size: .bits256)
        let sut = try TurningHarness(slotKey: .device(deviceKey), deviceKey: deviceKey, transition: nil)
        let before = try sut.fileSystem.contents(of: sut.encryptedFileURL)

        #expect(try sut.recovery.recoverAtLaunch() == .deviceKey)

        #expect(try sut.stateFile.read() == VaultStorageState(mode: .deviceKey, unlockDeadline: .seconds(1)))
        #expect(try sut.fileSystem.contents(of: sut.encryptedFileURL) == before)
    }

    /// An encrypted file with a vault in slot 6 wrapped with `slotKey`, and the state journaling `transition`.
    private struct TurningHarness {
        let fileSystem = InMemorySlotFileSystem()
        let deviceKeyStore: InMemoryDeviceKeyStore
        let directory = EncryptedVaultFixture.inMemoryDirectory

        init(slotKey: VaultSlotRootKey, deviceKey: SymmetricKey?, transition: VaultStorageState.Transition?) throws {
            deviceKeyStore = InMemoryDeviceKeyStore(key: deviceKey)
            var contents = try VaultSlotFile(kdfParameters: EncryptedVaultFixture.kdfParameters)
            try contents.createVault(
                inSlot: 6,
                rootKey: slotKey,
                payload: EncryptedVaultPayload.encode(.empty),
                wrappedAt: Date(),
            )
            try fileSystem.createFile(at: encryptedFileURL, contents: contents.bytes)
            let mode: VaultStorageState.Mode = transition == .turningOn || (transition == nil && deviceKey != nil)
                ? .deviceKey
                : .password
            try stateFile.write(VaultStorageState(mode: mode, transition: transition, unlockDeadline: .seconds(1)))
        }

        var encryptedFileURL: URL {
            directory.appending(path: EncryptedVaultFile.fileName)
        }

        var stateFile: VaultStorageStateFile {
            VaultStorageStateFile(directory: directory, fileSystem: fileSystem)
        }

        var recovery: VaultStorageRecovery {
            VaultStorageRecovery(directory: directory, fileSystem: fileSystem, deviceKeyStore: deviceKeyStore)
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
    func stateFile_update_changesOnlyWhatItChanges_andWritesNothingIfNothingChanged() async throws {
        let fileSystem = FaultInjectingSlotFileSystem(wrapping: InMemorySlotFileSystem())
        let file = VaultStorageStateFile(directory: EncryptedVaultFixture.inMemoryDirectory, fileSystem: fileSystem)
        try file.write(VaultStorageState(
            mode: .password,
            transition: .clearingSystemSurfaces,
            unlockDeadline: .seconds(2),
        ))

        let updated = try await file.update { $0.transition = nil }
        let steps = fileSystem.log.count
        let unchanged = try await file.update { $0.transition = nil }
        let secondUpdate = Array(fileSystem.log.dropFirst(steps))

        #expect(updated == VaultStorageState(mode: .password, unlockDeadline: .seconds(2)))
        #expect(unchanged == updated)
        #expect(try file.read() == updated)
        #expect(secondUpdate == [
            "lock vault-slots.lock",
            "read vault-storage-state.json",
            "unlock",
        ])
    }

    /// The AutoFill extension raises the deadline from its own process, so an update waits for the lock any process
    /// holds, as writers of the encrypted file do.
    @Test
    func stateFile_update_waitsForTheLockAnotherProcessHolds() async throws {
        let fileSystem = InMemorySlotFileSystem()
        let directory = EncryptedVaultFixture.inMemoryDirectory
        let file = VaultStorageStateFile(directory: directory, fileSystem: fileSystem)
        try file.write(VaultStorageState(mode: .password, unlockDeadline: .seconds(1)))
        let held = try await EncryptedVaultFile(directory: directory, fileSystem: fileSystem).lockUntilReleased()

        let raising = Task { try await file.raiseUnlockDeadline(to: .seconds(2)) }
        try await Task.sleep(for: .milliseconds(50))
        #expect(try file.read().unlockDeadline == .seconds(1))

        held.release()
        try await raising.value
        #expect(try file.read().unlockDeadline == .seconds(2))
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
