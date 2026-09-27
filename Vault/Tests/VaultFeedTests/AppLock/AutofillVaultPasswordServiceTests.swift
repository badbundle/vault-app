import Foundation
import FoundationExtensions
import Testing
@testable import VaultFeed

/// `AutofillVaultPasswordService` over a real `VaultUnlockService`, with a file holding a vault, and the attempt
/// counter it shares with the app.
@MainActor
struct AutofillVaultPasswordServiceTests {
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

        await #expect(throws: AutofillVaultPasswordService.NotEnoughMemoryError.self) {
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

    /// The password counts as set whenever the vault isn't plain, including while it's being converted, or when the
    /// state can't be read: the extension mustn't open the vault on device authentication alone then.
    @Test(arguments: [
        (nil, false),
        (VaultStorageState(mode: .password), true),
        (VaultStorageState(mode: .password, transition: .clearingSystemSurfaces), true),
        (VaultStorageState(mode: .plain, transition: .encrypting), true),
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

        let sut = AutofillVaultPasswordService(
            directory: directory,
            session: VaultStoreSession(target: .locked),
            purgeVaultContents: {},
        )

        #expect(sut.isPasswordSet == isPasswordSet)
    }

    @Test
    func init_unreadableStorageState_countsThePasswordAsSet() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not json".utf8).write(to: directory.appending(path: VaultStorageStateFile.fileName))

        let sut = AutofillVaultPasswordService(
            directory: directory,
            session: VaultStoreSession(target: .locked),
            purgeVaultContents: {},
        )

        #expect(sut.isPasswordSet)
    }
}

// MARK: - Helpers

extension AutofillVaultPasswordServiceTests {
    private struct SUT {
        let service: AutofillVaultPasswordService
        let session: VaultStoreSession
        let file: EncryptedVaultFile
        let availableMemory: SharedMutex<Int?>
        let log: SharedMutex<[String]>
    }

    private func makeSUT(
        items: [VaultItem] = [],
        availableMemory: Int? = nil,
        purges: SharedMutex<Int> = SharedMutex(0),
    ) throws -> SUT {
        var contents = try VaultSlotFile(kdfParameters: EncryptedVaultFixture.kdfParameters)
        try contents.createVault(
            inSlot: 3,
            rootKey: contents.header.passwordKey(for: Self.password),
            payload: EncryptedVaultPayload.encode(EncryptedVaultStoreTests.state(items: items)),
            wrappedAt: Date(),
        )
        let fileSystem = InMemorySlotFileSystem()
        let file = EncryptedVaultFile(directory: EncryptedVaultFixture.inMemoryDirectory, fileSystem: fileSystem)
        try fileSystem.createFile(at: file.url, contents: contents.bytes)

        let session = VaultStoreSession(target: .locked)
        let log = SharedMutex([String]())
        let clock = ManualUnlockClock()
        let memory = SharedMutex(availableMemory)
        let service = AutofillVaultPasswordService(
            file: file,
            session: session,
            attemptCounter: AppLockPasswordAttemptCounter(
                storage: LoggingAttemptStorage(log: log),
                clock: FakeAppLockClock(),
            ),
            deadlineStore: FakeUnlockDeadlineStore(deadline: .seconds(1)),
            purgeVaultContents: { purges.modify { $0 += 1 } },
            isPasswordSet: true,
            clock: clock,
            work: SpyUnlockWork(log: log, clock: clock),
            availableMemory: { memory.value },
            wrapStamper: .inMemory(),
        )
        return SUT(service: service, session: session, file: file, availableMemory: memory, log: log)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
