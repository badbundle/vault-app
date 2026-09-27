import Foundation
import FoundationExtensions
import TestHelpers
import Testing
@testable import VaultFeed

/// `AppLockPasswordUnlocker` over a real `VaultUnlockService`, with a file holding the real vault and a duress vault,
/// and a spy standing in for the erase, which `VaultEraserTests` covers.
@MainActor
struct AppLockPasswordUnlockerTests {
    private static let password = "correct horse"
    private static let duressPassword = "battery staple"
    private static let lastAttempt = AppLockPasswordAttemptCounter.eraseThreshold - 1

    @Test
    func unlock_rightPassword_isAccepted() async throws {
        let sut = try makeSUT()

        let result = try await sut.unlocker.unlock(password: Self.password)

        #expect(result == .accepted)
        #expect(await !sut.session.isLocked)
    }

    @Test
    func unlock_wrongPassword_isWrong() async throws {
        let sut = try makeSUT(erasesAfterFailedPasswords: true)

        let result = try await sut.unlocker.unlock(password: "wrong")

        #expect(result == .wrong)
        #expect(sut.log.value == ["count the attempt"])
    }

    @Test
    func unlock_whileTheUserMustWait_isDelayed() async throws {
        let sut = try makeSUT(erasesAfterFailedPasswords: true, wrongAttempts: 5, waitedOut: false)

        let result = try await sut.unlocker.unlock(password: Self.password)

        #expect(result == .delayed(.seconds(60)))
        #expect(sut.log.value.isEmpty)
    }

    /// The erase is done before the answer, so the lock screen never shows the password was wrong.
    @Test
    func unlock_tenthWrongWithErasingOn_erasesBeforeAnswering() async throws {
        let sut = try makeSUT(erasesAfterFailedPasswords: true, wrongAttempts: Self.lastAttempt)

        let result = try await sut.unlocker.unlock(password: "wrong")

        #expect(result == .erased)
        #expect(sut.log.value == ["count the attempt", "erase"])
    }

    @Test
    func unlock_tenthWrongWithErasingOff_isJustWrong() async throws {
        let sut = try makeSUT(erasesAfterFailedPasswords: false, wrongAttempts: Self.lastAttempt)

        let result = try await sut.unlocker.unlock(password: "wrong")

        #expect(result == .wrong)
        #expect(sut.log.value == ["count the attempt"])
    }

    @Test
    func unlock_ninthWrongWithErasingOn_isJustWrong() async throws {
        let sut = try makeSUT(erasesAfterFailedPasswords: true, wrongAttempts: Self.lastAttempt - 1)

        let result = try await sut.unlocker.unlock(password: "wrong")

        #expect(result == .wrong)
        #expect(sut.log.value == ["count the attempt"])
    }

    /// Ten wrong attempts counted already, with erasing on, is an erase that's due: a tenth the app stopped before
    /// acting on, or one in Settings. It erases before trying anything, so no password escapes it, the real one and a
    /// duress one included.
    @Test(
        arguments: [AppLockPasswordAttemptCounter.eraseThreshold, AppLockPasswordAttemptCounter.eraseThreshold + 3],
        ["right", "duress", "wrong"],
    )
    func unlock_eraseDue_erasesWithoutTryingThePassword(wrongAttempts: Int, entered: String) async throws {
        let sut = try makeSUT(erasesAfterFailedPasswords: true, wrongAttempts: wrongAttempts)
        let password = switch entered {
        case "right": Self.password
        case "duress": Self.duressPassword
        default: "wrong"
        }

        let result = try await sut.unlocker.unlock(password: password)

        #expect(result == .erased)
        #expect(sut.log.value == ["erase"])
        #expect(await sut.session.isLocked)
    }

    /// Even while the wait after the tenth isn't over: nothing's tried, so there's nothing to wait for.
    @Test
    func unlock_eraseDue_whileTheUserMustWait_erases() async throws {
        let sut = try makeSUT(
            erasesAfterFailedPasswords: true,
            wrongAttempts: Self.lastAttempt + 1,
            waitedOut: false,
        )

        let result = try await sut.unlocker.unlock(password: Self.password)

        #expect(result == .erased)
    }

    /// With erasing off, ten wrong ones only make the user wait, and the right password still opens the vault.
    @Test
    func unlock_tenCountedWithErasingOff_triesThePassword() async throws {
        let sut = try makeSUT(erasesAfterFailedPasswords: false, wrongAttempts: Self.lastAttempt + 1)

        let result = try await sut.unlocker.unlock(password: Self.password)

        #expect(result == .accepted)
        #expect(sut.log.value == ["count the attempt", "reset the count"])
    }

    /// The real password and a duress one alike: the vault opens, the count goes back to zero, and nothing is erased.
    @Test(arguments: [false, true])
    func unlock_rightPasswordAtTheLastAttempt_opensAVaultAndResetsTheCount(isDuress: Bool) async throws {
        let sut = try makeSUT(erasesAfterFailedPasswords: true, wrongAttempts: Self.lastAttempt)

        let result = try await sut.unlocker.unlock(password: isDuress ? Self.duressPassword : Self.password)

        #expect(result == .accepted)
        #expect(await !sut.session.isLocked)
        #expect(sut.log.value == ["count the attempt", "reset the count"])
        #expect(try sut.attemptStorage.load() == nil)
    }

    /// The blocker from review: the right password at the last attempt, whose result is thrown away because the app
    /// locked meanwhile, as when a call comes in. It resets the count all the same, so the next attempt with it opens
    /// the vault rather than erasing.
    @Test(arguments: [false, true])
    func unlock_rightPasswordThrownAwayAtTheLastAttempt_thenOpensTheVault(isDuress: Bool) async throws {
        let sut = try makeSUT(erasesAfterFailedPasswords: true, wrongAttempts: Self.lastAttempt)
        let password = isDuress ? Self.duressPassword : Self.password
        sut.clock.hold()
        let unlocker = sut.unlocker
        let attempt = Task { try await unlocker.unlock(password: password) }
        // However long it takes to get there: the lock has to land while the attempt is waiting out its deadline.
        while sut.clock.sleeps.isEmpty {
            try await Task.sleep(for: .milliseconds(1))
        }
        await sut.unlockService.lock()
        sut.clock.release()
        await #expect(throws: CancellationError.self) {
            try await attempt.value
        }

        let result = try await sut.unlocker.unlock(password: password)

        #expect(result == .accepted)
        #expect(sut.log.value == ["count the attempt", "reset the count", "count the attempt", "reset the count"])
    }

    /// A wrong tenth attempt thrown away stays counted, as one the app was stopped in the middle of would: the next
    /// attempt erases, whatever it is.
    @Test
    func unlock_wrongPasswordThrownAwayAtTheLastAttempt_thenErases() async throws {
        let sut = try makeSUT(erasesAfterFailedPasswords: true, wrongAttempts: Self.lastAttempt)
        sut.clock.hold()
        let unlocker = sut.unlocker
        let attempt = Task { try await unlocker.unlock(password: "wrong") }
        // However long it takes to get there: the lock has to land while the attempt is waiting out its deadline.
        while sut.clock.sleeps.isEmpty {
            try await Task.sleep(for: .milliseconds(1))
        }
        await sut.unlockService.lock()
        sut.clock.release()
        await #expect(throws: CancellationError.self) {
            try await attempt.value
        }

        let result = try await sut.unlocker.unlock(password: Self.password)

        #expect(result == .erased)
        #expect(sut.log.value == ["count the attempt", "erase"])
    }

    /// An erase that failed once it had journaled itself, reset the count and turned erasing off (here, when the
    /// fresh store couldn't be made). No vault can open while the journal's there, so the next attempt finishes it,
    /// whatever the password, with nothing counted and erasing off.
    @Test
    func unlock_afterAnEraseFailedPartWay_finishesIt() async throws {
        let sut = try makeSUT(erasesAfterFailedPasswords: true, wrongAttempts: Self.lastAttempt)
        let (storage, settings, deadlineStore) = (sut.attemptStorage, sut.settings, sut.deadlineStore)
        sut.eraser.onNextErase = {
            deadlineStore.startErasing()
            try storage.remove()
            settings.erasesAfterFailedPasswords = false
            throw EraseSpy.Failure()
        }
        await #expect(throws: EraseSpy.Failure.self) {
            try await sut.unlocker.unlock(password: "wrong")
        }
        #expect(try sut.attemptStorage.load() == nil)
        #expect(!sut.settings.erasesAfterFailedPasswords)

        let result = try await sut.unlocker.unlock(password: Self.password)

        #expect(result == .erased)
        #expect(sut.log.value == ["count the attempt", "erase", "reset the count", "erase"])
        #expect(await sut.session.isLocked)
    }
}

// MARK: - Helpers

extension AppLockPasswordUnlockerTests {
    private struct SUT {
        let unlocker: AppLockPasswordUnlocker
        let unlockService: VaultUnlockService
        let session: VaultStoreSession
        let clock: ManualUnlockClock
        let settings: AppLockSettingsStore
        /// What the attempt counter and the erase did, in order.
        let log: SharedMutex<[String]>
        let attemptStorage: LoggingAttemptStorage
        let deadlineStore: FakeUnlockDeadlineStore
        let eraser: EraseSpy
    }

    /// The erase the app does, logged with the attempts.
    @MainActor
    private final class EraseSpy {
        struct Failure: Error {}

        private let log: SharedMutex<[String]>
        /// What the next erase does, after it's logged, as far as it gets.
        var onNextErase: (() throws -> Void)?

        init(log: SharedMutex<[String]>) {
            self.log = log
        }

        func erase() throws {
            log.modify { $0.append("erase") }
            let next = onNextErase
            onNextErase = nil
            try next?()
        }
    }

    /// A file with the real vault in one slot and a duress vault in another. `wrongAttempts` wrong passwords in a row
    /// have been tried already, just now, and the wait after them is over unless `waitedOut` is false.
    private func makeSUT(
        erasesAfterFailedPasswords: Bool = false,
        wrongAttempts: Int = 0,
        waitedOut: Bool = true,
    ) throws -> SUT {
        var contents = try VaultSlotFile(kdfParameters: EncryptedVaultFixture.kdfParameters)
        try contents.createVault(
            inSlot: 3,
            rootKey: contents.header.passwordKey(for: Self.password),
            payload: EncryptedVaultPayload.encode(EncryptedVaultStoreTests.state(items: [uniqueVaultItem()])),
            wrappedAt: Date(),
        )
        try contents.createVault(
            inSlot: 12,
            rootKey: contents.header.passwordKey(for: Self.duressPassword),
            payload: EncryptedVaultPayload.encode(EncryptedVaultStoreTests.state(items: [])),
            wrappedAt: Date(),
        )
        let fileSystem = InMemorySlotFileSystem()
        let file = EncryptedVaultFile(directory: EncryptedVaultFixture.inMemoryDirectory, fileSystem: fileSystem)
        try fileSystem.createFile(at: file.url, contents: contents.bytes)
        try VaultStorageStateFile(directory: file.directory, fileSystem: fileSystem)
            .write(VaultStorageState(mode: .password))

        let session = VaultStoreSession(target: .locked)
        let clock = ManualUnlockClock()
        let log = SharedMutex([String]())
        let attemptStorage = LoggingAttemptStorage(log: log)
        let counterClock = FakeAppLockClock()
        if wrongAttempts > 0 {
            attemptStorage.setRecord(count: wrongAttempts, latestAt: counterClock.now)
            if waitedOut {
                counterClock.advance(by: .seconds(60 * 60))
            }
        }
        let deadlineStore = FakeUnlockDeadlineStore(deadline: .seconds(1))
        let attemptCounter = AppLockPasswordAttemptCounter(storage: attemptStorage, clock: counterClock)
        let unlockService = VaultUnlockService(
            file: file,
            session: session,
            attemptCounter: attemptCounter,
            deadlineStore: deadlineStore,
            purgeVaultContents: {},
            clock: clock,
            // The derivation's own log isn't this test's business.
            work: SpyUnlockWork(log: SharedMutex([String]()), clock: clock),
            availableMemory: { nil },
            wrapStamper: .inMemory(),
        )
        let settings = try AppLockSettingsStore(userDefaults: .nonPersistent())
        settings.erasesAfterFailedPasswords = erasesAfterFailedPasswords
        let eraser = EraseSpy(log: log)
        let unlocker = AppLockPasswordUnlocker(
            unlockService: unlockService,
            attemptCounter: attemptCounter,
            settings: settings,
        ) {
            try eraser.erase()
        }
        return SUT(
            unlocker: unlocker,
            unlockService: unlockService,
            session: session,
            clock: clock,
            settings: settings,
            log: log,
            attemptStorage: attemptStorage,
            deadlineStore: deadlineStore,
            eraser: eraser,
        )
    }
}
