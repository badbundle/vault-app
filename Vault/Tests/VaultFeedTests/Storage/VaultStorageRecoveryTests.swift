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

    /// An erase removed the vault but couldn't journal it, as it can if the disk is full. The count of wrong attempts
    /// shows it was meant, so recovery reports the erase to finish, rather than leave the device with no vault.
    @Test(arguments: [nil, VaultStorageState.Transition.clearingSystemSurfaces])
    func recover_encryptedWithNoVaultLeftAndTheEraseThresholdReached_reportsAnEraseToFinish(
        transition: VaultStorageState.Transition?,
    ) async throws {
        try await withTemporaryDirectory { directory in
            try Self.write(
                VaultStorageState(mode: .password, transition: transition, unlockDeadline: .seconds(1)),
                in: directory,
            )
            try Data("encrypted".utf8)
                .write(to: directory.appending(path: EncryptedVaultFile.temporaryFilePrefix + "a"))
            let attempts = Self.attempts(count: AppLockPasswordAttemptCounter.eraseThreshold)

            #expect(try Self.recovery(in: directory, attempts: attempts).recoverAtLaunch() == .erasing)
        }
    }

    /// The vault is gone, and nothing shows an erase was meant: a restore or a move to another iPhone may have brought
    /// the state back without the file. Erasing would delete every keychain item, and the file too if it turned up
    /// later, so recovery deletes nothing and leaves it to the user, whatever encrypted mode or change it finds.
    @Test(arguments: [nil, AppLockPasswordAttemptCounter.eraseThreshold - 1])
    func recover_encryptedWithNoVaultLeftAndNoSignOfAnErase_touchesNothing(count: Int?) async throws {
        for state in [
            VaultStorageState(mode: .password, unlockDeadline: .seconds(1)),
            VaultStorageState(mode: .deviceKey, unlockDeadline: .seconds(1)),
            VaultStorageState(mode: .password, transition: .turningOff, unlockDeadline: .seconds(1)),
        ] {
            try await withTemporaryDirectory { directory in
                try Self.write(state, in: directory)
                let attempts = Self.attempts(count: count)
                let deviceKeys = InMemoryDeviceKeyStore(key: SymmetricKey(size: .bits256))
                let before = try Self.fileNames(in: directory)

                #expect(throws: VaultStorageRecovery.Failure.vaultMissing, "\(state)") {
                    try Self.recovery(in: directory, attempts: attempts, deviceKeys: deviceKeys).recoverAtLaunch()
                }

                #expect(try Self.fileNames(in: directory) == before, "\(state)")
                #expect(try Self.read(in: directory) == state)
                #expect(deviceKeys.key != nil, "\(state)")
                #expect(try attempts.load()?.count == count, "\(state)")
            }
        }
    }

    /// A journaled erase is finished even with no vault left and no wrong attempts: the journal shows it was meant.
    @Test
    func recover_journaledEraseWithNoVaultLeft_reportsItToFinish() async throws {
        try await withTemporaryDirectory { directory in
            try Self.write(VaultStorageState(mode: .password, transition: .erasing), in: directory)

            #expect(try Self.recovery(in: directory, attempts: Self.attempts(count: nil)).recoverAtLaunch() == .erasing)
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
            EncryptedVaultFile.lockFileName,
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

    /// A clear that fails leaves the journal, so the next launch tries again.
    @Test
    func finishClearingSystemSurfaces_clearFails_keepsTheJournal() async throws {
        try await withTemporaryDirectory { directory in
            struct ClearFailure: Error {}
            let state = VaultStorageState(
                mode: .password,
                transition: .clearingSystemSurfaces,
                unlockDeadline: .seconds(1),
            )
            try Self.write(state, in: directory)
            let recovery = VaultStorageRecovery(directory: directory)

            await #expect(throws: ClearFailure.self) {
                try await recovery.finishClearingSystemSurfaces { throw ClearFailure() }
            }
            #expect(try Self.read(in: directory) == state)

            try await recovery.finishClearingSystemSurfaces {}
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

    /// No vault is left at all, as an erase that couldn't journal leaves it, and the count of wrong attempts shows it
    /// was meant: the erase has to finish, whatever the journal says was underway. Nothing else changes, and the device
    /// key stays for the erase to delete.
    @Test(arguments: [VaultStorageState.Transition.turningOff, .turningOn, nil])
    func recover_encryptedWithNoVaultLeft_reportsAnEraseToFinish(transition: VaultStorageState.Transition?) throws {
        let sut = try TurningHarness(
            slotKey: .password(derivedKey: SymmetricKey(size: .bits256)),
            deviceKey: SymmetricKey(size: .bits256),
            transition: transition,
        )
        try sut.fileSystem.removeItem(at: sut.encryptedFileURL)
        sut.attempts.setRecord(count: AppLockPasswordAttemptCounter.eraseThreshold, latestAt: .now)
        let before = try sut.stateFile.read()

        #expect(try sut.recovery.recoverAtLaunch() == .erasing)

        #expect(try sut.stateFile.read() == before)
        #expect(sut.deviceKeyStore.key != nil)
    }

    /// The app launches in the background while the device is locked. A file it can't read then is in the password
    /// form, as turning the password off makes it readable after the first unlock, and turning it on makes it
    /// unreadable while locked again. So the password is on, and the journal waits for the device to be unlocked.
    @Test(arguments: [VaultStorageState.Transition.turningOff, .turningOn])
    func recover_whileTurningThePasswordOffOrOn_onALockedDevice_isPasswordAndSettlesOnceUnlocked(
        transition: VaultStorageState.Transition,
    ) async throws {
        let sut = try TurningHarness(
            slotKey: .password(derivedKey: SymmetricKey(size: .bits256)),
            deviceKey: SymmetricKey(size: .bits256),
            transition: transition,
        )
        let journal = try sut.stateFile.read()
        sut.fileSystem.isDeviceLocked = true

        #expect(try sut.recovery.recoverAtLaunch() == .password)

        #expect(try sut.stateFile.read() == journal)
        #expect(sut.deviceKeyStore.key != nil)
        await #expect(throws: VaultStorageRecovery.Failure.fileUnreadableWhileLocked) {
            try await sut.recovery.settleTurningThePasswordOffOrOn()
        }

        sut.fileSystem.isDeviceLocked = false
        #expect(try await sut.recovery.settleTurningThePasswordOffOrOn() == .password)
        #expect(try sut.stateFile.read() == VaultStorageState(mode: .password, unlockDeadline: .seconds(1)))
        #expect(sut.deviceKeyStore.key == nil)
    }

    /// Turning the password back on stopped before its rekey: the device key still wraps the vault, and the file is
    /// readable after the first unlock, so it settles while the device is locked.
    @Test
    func recover_whileTurningThePasswordOn_beforeTheRekey_onALockedDevice_isDeviceKey() throws {
        let deviceKey = SymmetricKey(size: .bits256)
        let sut = try TurningHarness(slotKey: .device(deviceKey), deviceKey: deviceKey, transition: .turningOn)
        sut.fileSystem.isDeviceLocked = true

        #expect(try sut.recovery.recoverAtLaunch() == .deviceKey)

        #expect(try sut.stateFile.read() == VaultStorageState(mode: .deviceKey, unlockDeadline: .seconds(1)))
    }

    /// A device key left over with the password on, from a turn off that failed or a deletion that did, goes once
    /// it's shown to open nothing: not while the file can't be read.
    @Test
    func recover_passwordMode_deletesALeftoverDeviceKeyOnceItsShownToOpenNothing() throws {
        let sut = try TurningHarness(
            slotKey: .password(derivedKey: SymmetricKey(size: .bits256)),
            deviceKey: SymmetricKey(size: .bits256),
            transition: nil,
            mode: .password,
        )
        sut.fileSystem.isDeviceLocked = true

        #expect(try sut.recovery.recoverAtLaunch() == .password)
        #expect(sut.deviceKeyStore.key != nil)

        sut.fileSystem.isDeviceLocked = false
        #expect(try sut.recovery.recoverAtLaunch() == .password)
        #expect(sut.deviceKeyStore.key == nil)
    }

    /// Only a key that opens nothing goes.
    @Test
    func recover_passwordMode_keepsADeviceKeyThatOpensAVault() throws {
        let deviceKey = SymmetricKey(size: .bits256)
        let sut = try TurningHarness(
            slotKey: .device(deviceKey),
            deviceKey: deviceKey,
            transition: nil,
            mode: .password,
        )

        _ = try sut.recovery.recoverAtLaunch()

        #expect(sut.deviceKeyStore.key != nil)
    }

    /// The password is off, and the device key isn't there: an unencrypted computer backup restored onto another
    /// iPhone, say. Nothing opens the vault, so the app shows its failure screen.
    @Test
    func recover_deviceKeyMode_withoutADeviceKey_throwsDeviceKeyMissing() throws {
        let sut = try TurningHarness(
            slotKey: .device(SymmetricKey(size: .bits256)),
            deviceKey: nil,
            transition: nil,
            mode: .deviceKey,
        )

        #expect(throws: VaultStorageRecovery.Failure.deviceKeyMissing) {
            try sut.recovery.recoverAtLaunch()
        }
    }

    /// Recovery's state changes are made holding `vault-slots.lock`, so it waits for an extension's save or
    /// deadline raise to finish.
    @Test
    func recover_waitsForTheLockAnotherProcessHolds() async throws {
        let deviceKey = SymmetricKey(size: .bits256)
        let sut = try TurningHarness(slotKey: .device(deviceKey), deviceKey: deviceKey, transition: .turningOff)
        let held = try await EncryptedVaultFile(directory: sut.directory, fileSystem: sut.fileSystem)
            .lockUntilReleased()
        let recovery = sut.recovery

        let recovering = Task.detached { try recovery.recoverAtLaunch() }
        try await Task.sleep(for: .milliseconds(50))
        #expect(try sut.stateFile.read().transition == .turningOff)

        held.release()
        #expect(try await recovering.value == .deviceKey)
        #expect(try sut.stateFile.read().transition == nil)
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
        let attempts = LoggingAttemptStorage(log: SharedMutex([]))
        let directory = EncryptedVaultFixture.inMemoryDirectory

        /// - Parameter mode: The mode the state records. By default, the one the change started from, or with no
        ///   change, `deviceKey` if there's a device key.
        init(
            slotKey: VaultSlotRootKey,
            deviceKey: SymmetricKey?,
            transition: VaultStorageState.Transition?,
            mode: VaultStorageState.Mode? = nil,
        ) throws {
            deviceKeyStore = InMemoryDeviceKeyStore(key: deviceKey)
            var contents = try VaultSlotFile(kdfParameters: EncryptedVaultFixture.kdfParameters)
            try contents.createVault(
                inSlot: 6,
                rootKey: slotKey,
                payload: EncryptedVaultPayload.encode(.empty),
                wrappedAt: Date(),
            )
            // The file is readable after the first unlock only while the device key wraps the vault, as a rekey
            // leaves it.
            let protection: SlotFileProtection = slotKey.kind == .device
                ? .completeUntilFirstUserAuthentication
                : .complete
            try fileSystem.createFile(at: encryptedFileURL, contents: contents.bytes, protection: protection)
            let mode: VaultStorageState.Mode = mode
                ?? (transition == .turningOn || (transition == nil && deviceKey != nil) ? .deviceKey : .password)
            try stateFile.write(VaultStorageState(mode: mode, transition: transition, unlockDeadline: .seconds(1)))
        }

        var encryptedFileURL: URL {
            directory.appending(path: EncryptedVaultFile.fileName)
        }

        var stateFile: VaultStorageStateFile {
            VaultStorageStateFile(directory: directory, fileSystem: fileSystem)
        }

        var recovery: VaultStorageRecovery {
            VaultStorageRecovery(
                directory: directory,
                fileSystem: fileSystem,
                deviceKeyStore: deviceKeyStore,
                attemptStorage: attempts,
            )
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

        let updated = try await file.update { $0.transition = nil }.state
        let steps = fileSystem.log.count
        let unchanged = try await file.update { $0.transition = nil }.state
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

    /// The app stopped mid-erase. Recovery reports it, whatever the mode, and leaves finishing it to `VaultEraser`,
    /// which deletes the keychain items too: it deletes nothing itself, so no half-erased store opens meanwhile.
    @Test(arguments: [VaultStorageState.Mode.plain, .password])
    func recover_whileErasing_reportsItAndTouchesNothing(mode: VaultStorageState.Mode) async throws {
        try await withTemporaryDirectory { directory in
            try Self.makePlainStore(in: directory)
            try Self.makeEncryptedFiles(in: directory)
            try Self.write(VaultStorageState(mode: mode, transition: .erasing), in: directory)
            let before = try Self.fileNames(in: directory)

            #expect(try VaultStorageRecovery(directory: directory).recoverAtLaunch() == .erasing)

            #expect(try Self.fileNames(in: directory) == before)
            #expect(try Self.read(in: directory).transition == .erasing)
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
                VaultStorageState(mode: .plain, transition: .erasing),
                VaultStorageState(mode: .password, transition: .erasing),
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

    /// Recovery for a directory on disk, with the count of wrong attempts and the device key in memory.
    static func recovery(
        in directory: URL,
        attempts: LoggingAttemptStorage,
        deviceKeys: InMemoryDeviceKeyStore = InMemoryDeviceKeyStore(),
    ) -> VaultStorageRecovery {
        VaultStorageRecovery(
            directory: directory,
            fileSystem: LiveSlotFileSystem(),
            deviceKeyStore: deviceKeys,
            attemptStorage: attempts,
        )
    }

    /// A count of wrong attempts in a row, or none.
    static func attempts(count: Int?) -> LoggingAttemptStorage {
        let attempts = LoggingAttemptStorage(log: SharedMutex([]))
        if let count {
            attempts.setRecord(count: count, latestAt: .now)
        }
        return attempts
    }

    static func write(_ state: VaultStorageState, in directory: URL) throws {
        try VaultStorageStateFile(directory: directory).write(state)
    }

    static func read(in directory: URL) throws -> VaultStorageState {
        try VaultStorageStateFile(directory: directory).read()
    }

    /// The files in the directory, apart from `vault-slots.lock`, which recovery takes to change the state.
    static func fileNames(in directory: URL) throws -> Set<String> {
        try Set(FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)))
            .subtracting([EncryptedVaultFile.lockFileName])
    }
}
