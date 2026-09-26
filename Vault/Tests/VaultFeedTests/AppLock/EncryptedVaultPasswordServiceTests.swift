import Foundation
import FoundationExtensions
import Testing
@testable import VaultFeed

/// `EncryptedVaultPasswordService` over a real `VaultUnlockService`, with a file holding a vault, and the attempt
/// counter it shares with the app.
@MainActor
struct EncryptedVaultPasswordServiceTests {
    private static let password = "correct horse"

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

    @Test
    func isPasswordSet_isWhatItWasMadeWith() throws {
        #expect(try makeSUT(isPasswordSet: true).service.isPasswordSet)
        #expect(try !makeSUT(isPasswordSet: false).service.isPasswordSet)
    }

    /// Only the app's Settings set, change or turn off the password.
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
    }

    @Test
    func hasMemoryHeadroomToUnlock_notEnoughMemory_isFalse() async throws {
        let sut = try makeSUT(availableMemory: 1 << 20)

        #expect(try await !sut.service.hasMemoryHeadroomToUnlock())
    }

    @Test
    func hasMemoryHeadroomToUnlock_plentyOfMemory_isTrue() async throws {
        let sut = try makeSUT(availableMemory: 1 << 32)

        #expect(try await sut.service.hasMemoryHeadroomToUnlock())
    }

    @Test
    func lockVault_afterUnlocking_locksTheSessionAgain() async throws {
        let sut = try makeSUT(items: [uniqueVaultItem()])
        _ = try await sut.service.unlock(password: Self.password)

        await sut.service.lockVault()

        #expect(await sut.session.isLocked)
    }
}

// MARK: - Helpers

extension EncryptedVaultPasswordServiceTests {
    private struct SUT {
        let service: EncryptedVaultPasswordService
        let session: VaultStoreSession
    }

    private func makeSUT(
        items: [VaultItem] = [],
        isPasswordSet: Bool = true,
        availableMemory: Int? = nil,
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
        let attemptCounter = AppLockPasswordAttemptCounter(
            storage: LoggingAttemptStorage(log: log),
            clock: FakeAppLockClock(),
        )
        let unlockService = VaultUnlockService(
            file: file,
            session: session,
            attemptCounter: attemptCounter,
            deadlineStore: FakeUnlockDeadlineStore(deadline: .seconds(1)),
            purgeVaultContents: {},
            clock: clock,
            work: SpyUnlockWork(log: log, clock: clock),
            availableMemory: { availableMemory },
        )
        let service = EncryptedVaultPasswordService(
            unlockService: unlockService,
            attemptCounter: attemptCounter,
            isPasswordSet: isPasswordSet,
        )
        return SUT(service: service, session: session)
    }
}
