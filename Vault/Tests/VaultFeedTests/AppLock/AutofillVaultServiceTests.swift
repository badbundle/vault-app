import CryptoKit
import Foundation
import FoundationExtensions
import Testing
@testable import VaultFeed

/// `AutofillVaultService` over a real `VaultUnlockService`, with a file holding a vault, and the attempt
/// counter it shares with the app.
@MainActor
struct AutofillVaultServiceTests {
    private static let password = "correct horse"

    // MARK: - Unlocking

    @Test
    func unlock_rightPassword_isAcceptedAndOpensTheVault() async throws {
        let item = uniqueVaultItem()
        let sut = try makeSUT(items: [item])

        let result = try await sut.service.unlock(password: Self.password)

        #expect(result == .accepted)
        #expect(try await sut.session.retrieve(query: .init()).items == [item])
    }

    @Test
    func unlock_wrongPassword_isWrongAndOpensNothing() async throws {
        let sut = try makeSUT()

        let result = try await sut.service.unlock(password: "wrong")

        #expect(result == .wrong)
        #expect(await sut.session.isLocked)
    }

    /// Wrong passwords count with the same counter as the app's lock screen, and wait as long.
    @Test
    func unlock_afterFiveWrong_waitsAMinuteWithoutTrying() async throws {
        let sut = try makeSUT()
        for _ in 1 ... 5 {
            _ = try await sut.service.unlock(password: "wrong")
        }

        let result = try await sut.service.unlock(password: Self.password)

        #expect(result == .delayed(.seconds(60)))
        #expect(try await sut.service.remainingDelay() == .seconds(60))
        #expect(await sut.session.isLocked)
    }

    /// Only the app's Settings set, change or turn off the password, or make a duress vault.
    @Test
    func settingChangingOrTurningOff_throws() async throws {
        let service = try makeSUT().service

        await #expect(throws: AppLockPasswordUnavailableError.self) {
            try await service.setPassword(Self.password)
        }
        await #expect(throws: AppLockPasswordUnavailableError.self) {
            try await service.changePassword(current: Self.password, new: "battery staple")
        }
        await #expect(throws: AppLockPasswordUnavailableError.self) {
            try await service.turnOffPassword(current: Self.password)
        }
        await #expect(throws: AppLockPasswordUnavailableError.self) {
            try await service.makeDuressVault(password: "battery staple")
        }
    }

    // MARK: - Memory

    @Test
    func hasMemoryHeadroomToUnlock_followsTheMemoryLeft() async throws {
        let sut = try makeSUT(availableMemory: 1 << 20)
        #expect(try await !sut.service.hasMemoryHeadroomToUnlock())

        sut.availableMemory.modify { $0 = 1 << 32 }
        #expect(try await sut.service.hasMemoryHeadroomToUnlock())
    }

    /// An extension stopped mid-derivation would have counted the attempt as wrong, so without the memory nothing is
    /// counted or derived, and the sheet is told to send the user to Vault.
    @Test
    func unlock_notEnoughMemory_countsNothingAndSaysSo() async throws {
        let sut = try makeSUT(availableMemory: 1 << 20)
        var notified = false
        sut.service.onNotEnoughMemory = { notified = true }

        await #expect(throws: AutofillVaultService.NotEnoughMemoryError.self) {
            try await sut.service.unlock(password: Self.password)
        }

        #expect(notified)
        #expect(!sut.log.value.contains("count the attempt"))
        #expect(await sut.session.isLocked)
    }

    /// A save replaces the whole file, which takes memory too: without it, nothing is written.
    @Test
    func save_notEnoughMemory_writesNothingAndSaysSo() async throws {
        let sut = try makeSUT(availableMemory: 1 << 32)
        var notified = false
        sut.service.onNotEnoughMemory = { notified = true }
        _ = try await sut.service.unlock(password: Self.password)
        let fileBefore = try await sut.file.open()?.bytes

        sut.availableMemory.modify { $0 = 1 << 20 }
        await #expect(throws: EncryptedVaultStoreError.notEnoughMemory) {
            try await sut.session.insert(item: uniqueVaultItem().makeWritable())
        }

        for _ in 0 ..< 100 where !notified {
            await Task.yield()
        }
        #expect(notified)
        #expect(try await sut.file.open()?.bytes == fileBefore)
    }

    // MARK: - The device key

    /// With the password off, the device key opens the vault: nothing is counted, and no password is asked for.
    @Test
    func openWithDeviceKey_opensTheVaultTheDeviceKeyWraps() async throws {
        let item = uniqueVaultItem()
        let sut = try makeSUT(items: [item], wrappedWithTheDeviceKey: true)

        try await sut.service.openWithDeviceKey()

        #expect(try await sut.session.retrieve(query: .init()).items == [item])
        #expect(!sut.log.value.contains("count the attempt"))
    }

    @Test
    func openWithDeviceKey_notEnoughMemory_opensNothingAndSaysSo() async throws {
        let sut = try makeSUT(wrappedWithTheDeviceKey: true, availableMemory: 1 << 20)
        var notified = false
        sut.service.onNotEnoughMemory = { notified = true }

        await #expect(throws: AutofillVaultService.NotEnoughMemoryError.self) {
            try await sut.service.openWithDeviceKey()
        }

        #expect(notified)
        #expect(await sut.session.isLocked)
    }

    /// A HOTP increment with the device key goes through the encrypted file's lock and generation check, and needs
    /// the memory to replace the file, just as it does with the password.
    @Test
    func openWithDeviceKey_saveWithoutTheMemory_writesNothing() async throws {
        let sut = try makeSUT(wrappedWithTheDeviceKey: true, availableMemory: 1 << 32)
        try await sut.service.openWithDeviceKey()
        let fileBefore = try await sut.file.open()?.bytes

        sut.availableMemory.modify { $0 = 1 << 20 }
        await #expect(throws: EncryptedVaultStoreError.notEnoughMemory) {
            try await sut.session.insert(item: uniqueVaultItem().makeWritable())
        }

        #expect(try await sut.file.open()?.bytes == fileBefore)
    }

    // MARK: - The vault as it's stored now

    /// The app turned the password back on, or started an erase: the device key opens nothing, even if it's still
    /// there.
    @Test(arguments: [VaultAccessMode.password, .unavailable, .plain])
    func openWithDeviceKey_notInUseNow_opensNothing(mode: VaultAccessMode) async throws {
        let sut = try makeSUT(items: [uniqueVaultItem()], wrappedWithTheDeviceKey: true, accessMode: SharedMutex(mode))

        await #expect(throws: VaultUnlockError.deviceKeyNotInUse) {
            try await sut.service.openWithDeviceKey()
        }

        #expect(await sut.session.isLocked)
    }

    /// An AutoFill sheet left open in another app while the user turns the password on in Vault: the vault it opened
    /// reads nothing, and takes no change, from then on.
    @Test(arguments: [VaultAccessMode.password, .unavailable])
    func openWithDeviceKey_modeChangesWhileOpen_readsAndWritesNothing(mode: VaultAccessMode) async throws {
        let accessMode = SharedMutex(VaultAccessMode.deviceKey)
        let sut = try makeSUT(items: [uniqueVaultItem()], wrappedWithTheDeviceKey: true, accessMode: accessMode)
        try await sut.service.openWithDeviceKey()
        let fileBefore = try await sut.file.open()?.bytes

        accessMode.modify { $0 = mode }

        #expect(try await sut.session.retrieve(query: .init()).items.isEmpty)
        #expect(try await sut.session.hasAnyItems == false)
        await #expect(throws: VaultStoreSessionError.locked) {
            try await sut.session.insert(item: uniqueVaultItem().makeWritable())
        }
        #expect(try await sut.file.open()?.bytes == fileBefore)
    }

    /// A rekey or an erase changes the storage state before it changes the file, holding the file's lock. So a save
    /// checks again once it has the lock, and a change of mode just as it starts is caught.
    @Test
    func openWithDeviceKey_modeChangesAsASaveStarts_writesNothing() async throws {
        let accessMode = SharedMutex(VaultAccessMode.deviceKey)
        let sut = try makeSUT(wrappedWithTheDeviceKey: true, accessMode: accessMode)
        try await sut.service.openWithDeviceKey()
        let fileBefore = try await sut.file.open()?.bytes

        sut.whenAskedForMemory.modify { $0 = { accessMode.modify { $0 = .password } } }
        await #expect(throws: VaultStoreSessionError.locked) {
            try await sut.session.insert(item: uniqueVaultItem().makeWritable())
        }

        #expect(try await sut.file.open()?.bytes == fileBefore)
    }

    /// Likewise for a vault the password opened: once the password's off, or an erase has started, it reads nothing.
    @Test
    func unlock_modeChangesWhileOpen_readsNothing() async throws {
        let accessMode = SharedMutex(VaultAccessMode.password)
        let sut = try makeSUT(items: [uniqueVaultItem()], accessMode: accessMode)
        #expect(try await sut.service.unlock(password: Self.password) == .accepted)
        #expect(try await sut.session.retrieve(query: .init()).items.count == 1)

        accessMode.modify { $0 = .unavailable }

        #expect(try await sut.session.retrieve(query: .init()).items.isEmpty)
    }

    // MARK: - Showing with the device key

    /// For the widgets and QuickType: the vault is read without the file's lock, and nothing is left behind, not even
    /// a lock file, which an erase has to remove.
    @Test
    func openedToShowWithDeviceKey_readsTheVaultLeavingNothingBehind() async throws {
        let item = uniqueVaultItem()
        let sut = try makeSUT(items: [item], wrappedWithTheDeviceKey: true)
        let before = try sut.fileNames()

        let session = try await openToShow(sut, mode: .deviceKey)

        #expect(try await session.retrieve(query: .init()).items == [item])
        #expect(try sut.fileNames() == before)
    }

    @Test
    func openedToShowWithDeviceKey_refusesWrites() async throws {
        let sut = try makeSUT(items: [uniqueVaultItem()], wrappedWithTheDeviceKey: true)
        let session = try await openToShow(sut, mode: .deviceKey)
        let fileBefore = try await sut.file.open()?.bytes

        await #expect(throws: VaultStoreSessionError.locked) {
            try await session.insert(item: uniqueVaultItem().makeWritable())
        }
        await #expect(throws: VaultStoreSessionError.locked) {
            try await session.incrementCounter(id: .init())
        }
        #expect(try await sut.file.open()?.bytes == fileBefore)
    }

    @Test(arguments: [VaultAccessMode.password, .unavailable, .plain])
    func openedToShowWithDeviceKey_notInUseNow_opensNothing(mode: VaultAccessMode) async throws {
        let sut = try makeSUT(items: [uniqueVaultItem()], wrappedWithTheDeviceKey: true)
        let before = try sut.fileNames()

        await #expect(throws: VaultUnlockError.deviceKeyNotInUse) {
            try await openToShow(sut, mode: mode)
        }
        #expect(try sut.fileNames() == before)
    }

    @Test
    func retrieveAndLock_locksTheSessionAfterReading() async throws {
        let item = uniqueVaultItem()
        let session = VaultStoreSession(target: .plain(GatedVaultStore(items: [item])))

        let result = try await VaultStoreSession.retrieveAndLock { session }

        #expect(result.items == [item])
        #expect(await session.isLocked)
    }

    // MARK: - Locking

    @Test
    func lockVault_afterUnlocking_locksAndForgetsWhatWasRead() async throws {
        let purges = SharedMutex(0)
        let sut = try makeSUT(items: [uniqueVaultItem()], purges: purges)
        _ = try await sut.service.unlock(password: Self.password)

        await sut.service.lockVault()

        #expect(await sut.session.isLocked)
        #expect(purges.value == 1)
    }

    // MARK: - Storage state

    /// Only the app writes the storage state: however long an attempt takes, the extension leaves the deadline.
    @Test
    func deadlineStore_neverRaisesTheDeadline() async throws {
        let fileSystem = InMemorySlotFileSystem()
        let stateFile = VaultStorageStateFile(
            directory: EncryptedVaultFixture.inMemoryDirectory,
            fileSystem: fileSystem,
        )
        try stateFile.write(VaultStorageState(mode: .password, unlockDeadline: .seconds(1)))
        let sut = ReadOnlyUnlockDeadlineStore(stateFile: stateFile)

        try await sut.raiseUnlockDeadline(to: .seconds(3))

        #expect(try await sut.unlockDeadline() == .seconds(1))
    }

    /// The password counts as set whenever the vault doesn't open without it, including while it's being converted
    /// or rekeyed, or when the state can't be read: the extension mustn't open the vault on device authentication
    /// alone then. It's read afresh each time, since the app can turn the password on or off meanwhile.
    @Test(arguments: [
        (nil, false),
        (VaultStorageState(mode: .password), true),
        (VaultStorageState(mode: .password, transition: .clearingSystemSurfaces), true),
        (VaultStorageState(mode: .plain, transition: .encrypting), true),
        (VaultStorageState(mode: .deviceKey), false),
        (VaultStorageState(mode: .deviceKey, transition: .turningOn), true),
    ] as [(VaultStorageState?, Bool)])
    func init_readsWhetherThePasswordIsSetFromTheStorageState(
        state: VaultStorageState?,
        isPasswordSet: Bool,
    ) throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        if let state {
            try VaultStorageStateFile(directory: directory).write(state)
        }

        let sut = AutofillVaultService(
            directory: directory,
            session: VaultStoreSession(target: .locked),
            purgeVaultContents: {},
        )

        #expect(sut.isPasswordSet == isPasswordSet)
    }

    /// The password turned back on while the extension's process lived on: the same service needs it now.
    @Test
    func isPasswordSet_followsThePasswordTurnedBackOn() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let stateFile = VaultStorageStateFile(directory: directory)
        try stateFile.write(VaultStorageState(mode: .deviceKey))
        let sut = AutofillVaultService(
            directory: directory,
            session: VaultStoreSession(target: .locked),
            purgeVaultContents: {},
        )
        #expect(!sut.isPasswordSet)

        try stateFile.write(VaultStorageState(mode: .password))

        #expect(sut.isPasswordSet)
    }

    @Test
    func init_unreadableStorageState_countsThePasswordAsSet() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not json".utf8).write(to: directory.appending(path: VaultStorageStateFile.fileName))

        let sut = AutofillVaultService(
            directory: directory,
            session: VaultStoreSession(target: .locked),
            purgeVaultContents: {},
        )

        #expect(sut.isPasswordSet)
    }
}

// MARK: - Helpers

extension AutofillVaultServiceTests {
    private struct SUT {
        let service: AutofillVaultService
        let session: VaultStoreSession
        let file: EncryptedVaultFile
        let fileSystem: InMemorySlotFileSystem
        let deviceKeyStore: InMemoryDeviceKeyStore
        let availableMemory: SharedMutex<Int?>
        /// Runs whenever the memory left is asked for, as a save does just before it takes the file's lock.
        let whenAskedForMemory: SharedMutex<(@Sendable () -> Void)?>
        let log: SharedMutex<[String]>

        var directory: URL {
            EncryptedVaultFixture.inMemoryDirectory
        }

        func fileNames() throws -> Set<String> {
            try Set(fileSystem.contentsOfDirectory(at: directory).map(\.lastPathComponent))
        }
    }

    /// - Parameter accessMode: How the vault can be opened now, which the service checks as the extension's does, or
    ///   `nil` for no check.
    private func makeSUT(
        items: [VaultItem] = [],
        wrappedWithTheDeviceKey: Bool = false,
        availableMemory: Int? = nil,
        accessMode: SharedMutex<VaultAccessMode>? = nil,
        purges: SharedMutex<Int> = SharedMutex(0),
    ) throws -> SUT {
        var contents = try VaultSlotFile(kdfParameters: EncryptedVaultFixture.kdfParameters)
        let deviceKey = SymmetricKey(size: .bits256)
        try contents.createVault(
            inSlot: 3,
            rootKey: wrappedWithTheDeviceKey
                ? .device(deviceKey)
                : contents.header.passwordKey(for: Self.password),
            payload: EncryptedVaultPayload.encode(EncryptedVaultStoreTests.state(items: items)),
            wrappedAt: Date(),
        )
        let fileSystem = InMemorySlotFileSystem()
        let file = EncryptedVaultFile(directory: EncryptedVaultFixture.inMemoryDirectory, fileSystem: fileSystem)
        try fileSystem.createFile(at: file.url, contents: contents.bytes)

        try VaultStorageStateFile(directory: file.directory, fileSystem: fileSystem).write(VaultStorageState(
            mode: wrappedWithTheDeviceKey ? .deviceKey : .password,
            unlockDeadline: .seconds(1),
        ))

        let session = VaultStoreSession(target: .locked)
        let log = SharedMutex([String]())
        let clock = ManualUnlockClock()
        let memory = SharedMutex(availableMemory)
        let whenAskedForMemory = SharedMutex<(@Sendable () -> Void)?>(nil)
        let deviceKeyStore = InMemoryDeviceKeyStore(key: wrappedWithTheDeviceKey ? deviceKey : nil)
        let askForMemory: @Sendable () -> Int? = {
            whenAskedForMemory.value?()
            return memory.value
        }
        var currentAccessMode: (@Sendable () -> VaultAccessMode)?
        if let accessMode {
            currentAccessMode = { accessMode.value }
        }
        let service = AutofillVaultService(
            file: file,
            session: session,
            attemptCounter: AppLockPasswordAttemptCounter(
                storage: LoggingAttemptStorage(log: log),
                clock: FakeAppLockClock(),
            ),
            deadlineStore: FakeUnlockDeadlineStore(deadline: .seconds(1)),
            deviceKeyStore: deviceKeyStore,
            purgeVaultContents: { purges.modify { $0 += 1 } },
            needsPassword: { !wrappedWithTheDeviceKey },
            clock: clock,
            work: SpyUnlockWork(log: log, clock: clock),
            availableMemory: askForMemory,
            wrapStamper: .inMemory(),
            currentAccessMode: currentAccessMode,
        )
        return SUT(
            service: service,
            session: session,
            file: file,
            fileSystem: fileSystem,
            deviceKeyStore: deviceKeyStore,
            availableMemory: memory,
            whenAskedForMemory: whenAskedForMemory,
            log: log,
        )
    }

    private func openToShow(_ sut: SUT, mode: VaultAccessMode) async throws -> VaultStoreSession {
        try await VaultStoreSession.openedToShowWithDeviceKey(
            file: EncryptedVaultFile(directory: sut.directory, fileSystem: sut.fileSystem),
            stateFile: VaultStorageStateFile(directory: sut.directory, fileSystem: sut.fileSystem),
            deviceKeyStore: sut.deviceKeyStore,
            currentAccessMode: { mode },
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
