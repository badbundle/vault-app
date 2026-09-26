import Foundation
import TestHelpers
import Testing
@testable import VaultFeed

/// `AppLockService` with the App Lock Password: the lock screen's password step, and setting, changing and turning
/// off the password.
@MainActor
struct AppLockServicePasswordTests {
    private static let password = "correct horse"

    // MARK: - Launch

    @Test
    func init_noPasswordService_offersNoPassword() throws {
        let sut = try makeSUT(isEnabled: true, passwordService: nil)

        #expect(!sut.offersPassword)
        #expect(!sut.isPasswordSet)
    }

    @Test
    func init_passwordSet_startsLockedEvenWithTheLockOff() throws {
        let sut = try makeSUT(isEnabled: false, passwordService: FakeAppLockPasswordService(password: Self.password))

        #expect(sut.offersPassword)
        #expect(sut.isPasswordSet)
        #expect(sut.isEnabled)
        #expect(sut.state == .locked(.init(step: .deviceAuthentication)))
    }

    // MARK: - Unlocking

    @Test
    func unlock_passwordSet_asksForThePasswordAfterDeviceAuthentication() async throws {
        let sut = try makeSUT(passwordService: FakeAppLockPasswordService(password: Self.password))

        await sut.unlock()

        #expect(sut.state == .locked(.init(step: .password)))
    }

    @Test
    func unlock_noPasswordSet_unlocksWithDeviceAuthenticationAlone() async throws {
        let sut = try makeSUT(isEnabled: true, passwordService: FakeAppLockPasswordService())

        await sut.unlock()

        #expect(sut.state == .unlocked)
    }

    @Test
    func unlock_deviceAuthenticationFails_neverAsksForThePassword() async throws {
        let sut = try makeSUT(
            policy: .alwaysDeny,
            passwordService: FakeAppLockPasswordService(password: Self.password),
        )

        await sut.unlock()

        #expect(sut.state == .locked(.init(step: .deviceAuthentication, failure: .failed)))
    }

    @Test
    func unlockWithPassword_right_unlocksAndRunsWhatWasWaiting() async throws {
        let sut = try makeSUT(passwordService: FakeAppLockPasswordService(password: Self.password))
        var didRun = false
        sut.performWhenUnlocked { didRun = true }
        await sut.unlock()

        await sut.unlock(password: Self.password)

        #expect(sut.state == .unlocked)
        #expect(didRun)
    }

    @Test
    func unlockWithPassword_wrong_staysOnThePasswordAndSaysSo() async throws {
        let sut = try makeSUT(passwordService: FakeAppLockPasswordService(password: Self.password))
        await sut.unlock()

        await sut.unlock(password: "wrong")

        #expect(sut.state == .locked(.init(step: .password, failure: .wrongPassword)))
    }

    @Test
    func unlockWithPassword_fifthWrongInARow_waitsAMinute() async throws {
        let clock = FakeAppLockClock()
        let sut = try makeSUT(
            clock: clock,
            passwordService: FakeAppLockPasswordService(password: Self.password, clock: clock),
        )
        await sut.unlock()

        for _ in 1 ... 5 {
            await sut.unlock(password: "wrong")
        }

        let expected = AppLockedState(
            step: .password,
            failure: .wrongPassword,
            passwordRetryAt: clock.now.advanced(by: .seconds(60)),
        )
        #expect(sut.state == .locked(expected))
    }

    @Test
    func unlockWithPassword_whileWaiting_triesNothingAndSaysHowLong() async throws {
        let clock = FakeAppLockClock()
        let service = FakeAppLockPasswordService(password: Self.password, wrongAttempts: 5, clock: clock)
        let sut = try makeSUT(clock: clock, passwordService: service)
        await sut.unlock()
        clock.advance(by: .seconds(20))

        await sut.unlock(password: Self.password)

        let expected = AppLockedState(step: .password, passwordRetryAt: clock.now.advanced(by: .seconds(40)))
        #expect(sut.state == .locked(expected))
    }

    @Test
    func unlock_passwordWaiting_showsThePasswordStepAlreadyWaiting() async throws {
        let clock = FakeAppLockClock()
        let service = FakeAppLockPasswordService(password: Self.password, wrongAttempts: 6, clock: clock)
        let sut = try makeSUT(clock: clock, passwordService: service)

        await sut.unlock()

        let expected = AppLockedState(step: .password, passwordRetryAt: clock.now.advanced(by: .seconds(5 * 60)))
        #expect(sut.state == .locked(expected))
    }

    @Test
    func unlockWithPassword_serviceFails_saysItCouldNotCheck() async throws {
        let service = FakeAppLockPasswordService(password: Self.password)
        let sut = try makeSUT(passwordService: service)
        await sut.unlock()
        service.failure = TestError()

        await sut.unlock(password: Self.password)

        #expect(sut.state == .locked(.init(step: .password, failure: .failed)))
    }

    @Test
    func unlockWithPassword_beforeDeviceAuthentication_doesNothing() async throws {
        let sut = try makeSUT(passwordService: FakeAppLockPasswordService(password: Self.password))

        await sut.unlock(password: Self.password)

        #expect(sut.state == .locked(.init(step: .deviceAuthentication)))
    }

    @Test
    func unlock_onThePasswordStep_doesNotAskForDeviceAuthenticationAgain() async throws {
        let sut = try makeSUT(passwordService: FakeAppLockPasswordService(password: Self.password))
        await sut.unlock()

        await sut.unlock()

        #expect(sut.state == .locked(.init(step: .password)))
    }

    @Test
    func leavingTheForeground_onThePasswordStep_startsAgainWithDeviceAuthentication() async throws {
        let sut = try makeSUT(passwordService: FakeAppLockPasswordService(password: Self.password))
        await sut.unlock()

        sut.scenePhaseDidChange(to: .background)

        #expect(sut.state == .locked(.init(step: .deviceAuthentication)))
    }

    // MARK: - The lock's toggle

    @Test
    func setEnabled_off_whilePasswordSet_staysOn() async throws {
        let sut = try await makeUnlockedSUT(passwordService: FakeAppLockPasswordService(password: Self.password))

        await sut.setEnabled(false)

        #expect(!sut.canDisable)
        #expect(sut.isEnabled)
    }

    // MARK: - Setting the password

    @Test
    func setPassword_authenticated_setsItAndTellsTheExtensions() async throws {
        let didChangeSettings = Counter()
        let sut = try makeSUT(
            isEnabled: false,
            passwordService: FakeAppLockPasswordService(),
            didChangeSettings: didChangeSettings,
        )

        let didSet = try await sut.setPassword(Self.password)

        #expect(didSet)
        #expect(sut.isPasswordSet)
        #expect(sut.isEnabled)
        #expect(didChangeSettings.count == 1)
    }

    @Test
    func setPassword_notAuthenticated_changesNothing() async throws {
        let sut = try makeSUT(isEnabled: false, policy: .alwaysDeny, passwordService: FakeAppLockPasswordService())

        let didSet = try await sut.setPassword(Self.password)

        #expect(!didSet)
        #expect(!sut.isPasswordSet)
    }

    @Test
    func setPassword_fails_throwsAndChangesNothing() async throws {
        let service = FakeAppLockPasswordService()
        service.failure = TestError()
        let sut = try makeSUT(isEnabled: false, passwordService: service)

        await #expect(throws: TestError.self) {
            try await sut.setPassword(Self.password)
        }
        #expect(!sut.isPasswordSet)
        #expect(!sut.isChangingSettings)
    }

    @Test
    func setPassword_noPasswordService_throws() async throws {
        let sut = try makeSUT(isEnabled: false, passwordService: nil)

        await #expect(throws: AppLockPasswordUnavailableError.self) {
            try await sut.setPassword(Self.password)
        }
    }

    @Test
    func setPassword_whileLocked_throws() async throws {
        let sut = try makeSUT(isEnabled: true, passwordService: FakeAppLockPasswordService())

        await #expect(throws: AppLockPasswordUnavailableError.self) {
            try await sut.setPassword(Self.password)
        }
    }

    // MARK: - Changing and turning off the password

    @Test
    func changePassword_right_changesIt() async throws {
        let service = FakeAppLockPasswordService(password: Self.password)
        let sut = try await makeUnlockedSUT(passwordService: service)

        let result = try await sut.changePassword(current: Self.password, new: "battery staple")

        #expect(result == .accepted)
        #expect(try await service.unlock(password: "battery staple") == .accepted)
    }

    @Test
    func changePassword_wrong_countsAsAWrongAttempt() async throws {
        let clock = FakeAppLockClock()
        let service = FakeAppLockPasswordService(password: Self.password, clock: clock)
        let sut = try await makeUnlockedSUT(passwordService: service, clock: clock)

        var results = [AppLockPasswordResult]()
        for _ in 1 ... 5 {
            try await results.append(sut.changePassword(current: "wrong", new: "battery staple"))
        }

        #expect(results == Array(repeating: .wrong, count: 5))
        #expect(await sut.passwordRetryTime() == clock.now.advanced(by: .seconds(60)))
    }

    @Test
    func turnOffPassword_right_turnsItOffAndLeavesTheLockOn() async throws {
        let didChangeSettings = Counter()
        let sut = try await makeUnlockedSUT(
            passwordService: FakeAppLockPasswordService(password: Self.password),
            didChangeSettings: didChangeSettings,
        )

        let result = try await sut.turnOffPassword(current: Self.password)

        #expect(result == .accepted)
        #expect(!sut.isPasswordSet)
        #expect(sut.canDisable)
        #expect(sut.isEnabled)
        #expect(didChangeSettings.count == 1)
    }

    @Test
    func turnOffPassword_wrong_leavesItOn() async throws {
        let sut = try await makeUnlockedSUT(passwordService: FakeAppLockPasswordService(password: Self.password))

        let result = try await sut.turnOffPassword(current: "wrong")

        #expect(result == .wrong)
        #expect(sut.isPasswordSet)
    }

    @Test
    func turnOffPassword_whileWaiting_triesNothing() async throws {
        let clock = FakeAppLockClock()
        let service = FakeAppLockPasswordService(password: Self.password, clock: clock)
        let sut = try await makeUnlockedSUT(passwordService: service, clock: clock)
        for _ in 1 ... 5 {
            _ = try await sut.turnOffPassword(current: "wrong")
        }

        let result = try await sut.turnOffPassword(current: Self.password)

        #expect(result == .delayed(.seconds(60)))
        #expect(sut.isPasswordSet)
    }
}

// MARK: - Helpers

extension AppLockServicePasswordTests {
    private func makeSUT(
        isEnabled: Bool = true,
        policy: any DeviceAuthenticationPolicy = .alwaysAllow,
        clock: FakeAppLockClock = FakeAppLockClock(),
        passwordService: FakeAppLockPasswordService?,
        didChangeSettings: Counter = Counter(),
    ) throws -> AppLockService {
        let settings = try AppLockSettingsStore(userDefaults: .nonPersistent())
        settings.isEnabled = isEnabled
        return AppLockService(
            settings: settings,
            authenticationService: DeviceAuthenticationService(policy: policy),
            passwordService: passwordService,
            clock: clock,
            purgeSensitiveData: {},
            didChangeSettings: { didChangeSettings.increment() },
        )
    }

    /// Unlocked with the password, as Settings always is.
    private func makeUnlockedSUT(
        passwordService: FakeAppLockPasswordService,
        clock: FakeAppLockClock = FakeAppLockClock(),
        didChangeSettings: Counter = Counter(),
    ) async throws -> AppLockService {
        let sut = try makeSUT(clock: clock, passwordService: passwordService, didChangeSettings: didChangeSettings)
        await sut.unlock()
        await sut.unlock(password: Self.password)
        #expect(sut.state == .unlocked)
        return sut
    }
}

@MainActor
private final class Counter {
    private(set) var count = 0

    func increment() {
        count += 1
    }
}
