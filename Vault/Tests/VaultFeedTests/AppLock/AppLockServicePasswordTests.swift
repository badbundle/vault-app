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

    /// With the password off after being on, device authentication is the only step, and it opens the vault, which
    /// is encrypted with a key on the device.
    @Test
    func unlock_noPasswordSet_opensTheVaultWithoutAPassword() async throws {
        let service = FakeAppLockPasswordService()
        let sut = try makeSUT(isEnabled: true, passwordService: service)
        await service.lockVault()

        await sut.unlock()

        #expect(sut.state == .unlocked)
        #expect(service.isVaultOpen)
    }

    @Test
    func unlock_vaultDoesNotOpenWithoutAPassword_staysLocked() async throws {
        let service = FakeAppLockPasswordService()
        service.failure = TestError()
        let sut = try makeSUT(isEnabled: true, passwordService: service)

        await sut.unlock()

        #expect(sut.state == .locked(.init(step: .deviceAuthentication, failure: .failed)))
    }

    /// Opening the vault waits for the password: device authentication alone doesn't open it.
    @Test
    func unlock_passwordSet_doesNotOpenTheVaultAfterDeviceAuthentication() async throws {
        let service = FakeAppLockPasswordService(password: Self.password)
        let sut = try makeSUT(passwordService: service)
        await service.lockVault()

        await sut.unlock()

        #expect(!service.isVaultOpen)
    }

    /// The app locking locks the vault too, so its keys and what was read from it go.
    @Test
    func lock_locksTheVault() async throws {
        let service = FakeAppLockPasswordService(password: Self.password)
        let sut = try await makeUnlockedSUT(passwordService: service)
        #expect(service.isVaultOpen)

        sut.scenePhaseDidChange(to: .background)
        await sut.vaultLock?.value

        #expect(!service.isVaultOpen)
        #expect(sut.isLocked)
    }

    /// The app locks while the password is tried, and the attempt opens the vault after the lock has locked it. The
    /// attempt's result is thrown away, and the vault is locked again.
    @Test
    func lock_whileThePasswordIsTried_locksTheVaultAgainAfterTheAttempt() async throws {
        let service = FakeAppLockPasswordService(password: Self.password)
        let sut = try makeSUT(passwordService: service)
        await sut.unlock()
        service.whileUnlocking = { [weak sut] in
            sut?.scenePhaseDidChange(to: .background)
        }

        await sut.unlock(password: Self.password)
        await sut.vaultLock?.value

        #expect(sut.isLocked)
        #expect(!service.isVaultOpen)
    }

    /// With the lock off and the password off after being on, the vault opens at launch without asking, and a widget's
    /// link waiting for the app to be unlocked finds it open.
    @Test
    func openVaultIfUnlocked_lockOff_opensTheVaultBeforeWaitingActionsRun() async throws {
        let service = FakeAppLockPasswordService()
        await service.lockVault()
        let sut = try makeSUT(isEnabled: false, passwordService: service)

        sut.openVaultIfUnlocked()
        let foundItOpen = BoolBox()
        sut.performWhenUnlocked {
            foundItOpen.value = service.isVaultOpen
        }
        await sut.vaultOpening?.value
        for _ in 0 ..< 10 where foundItOpen.value == nil {
            await Task.yield()
        }

        #expect(foundItOpen.value == true)
    }

    /// Setting the password while the app locks, then passes device authentication again before the conversion ends,
    /// locks the app again once it's set, so the password is asked for.
    @Test
    func setPassword_appLockedMeanwhile_locksTheAppAgainOnceSet() async throws {
        // Long enough that the conversion is still underway once the app has unlocked again, even on a busy machine.
        let service = FakeAppLockPasswordService(deadline: .seconds(1))
        let sut = try makeSUT(isEnabled: true, passwordService: service)
        sut.scenePhaseDidChange(to: .active)
        await sut.automaticUnlock?.value
        let lockedMeanwhile = BoolBox()
        service.whileSettingPassword = { [weak sut] in
            sut?.scenePhaseDidChange(to: .background)
            sut?.scenePhaseDidChange(to: .active)
            lockedMeanwhile.value = true
        }

        let setting = Task { try await sut.setPassword(Self.password) }
        for _ in 0 ..< 1000 where lockedMeanwhile.value == nil {
            try await Task.sleep(for: .milliseconds(1))
        }
        try #require(lockedMeanwhile.value == true)
        await sut.automaticUnlock?.value
        #expect(!sut.isLocked)
        #expect(try await setting.value)
        await sut.vaultLock?.value

        #expect(sut.state == .locked(.init(step: .deviceAuthentication)))
        #expect(!service.isVaultOpen)
    }

    /// While the password is set, the device locking locks the app and the vault, whatever the delay, so the vault's
    /// keys aren't in memory while the device is locked.
    @Test
    func deviceWillLock_passwordSet_locksTheAppAndTheVaultWhateverTheDelay() async throws {
        let service = FakeAppLockPasswordService(password: Self.password)
        let sut = try await makeUnlockedSUT(passwordService: service, delay: .fifteenMinutes)
        sut.scenePhaseDidChange(to: .background)
        #expect(!sut.isLocked)

        sut.deviceWillLock()
        await sut.vaultLock?.value

        #expect(sut.isLocked)
        #expect(!service.isVaultOpen)
    }

    @Test
    func deviceWillLock_noPasswordSet_leavesTheDelayAlone() async throws {
        let sut = try makeSUT(isEnabled: true, passwordService: FakeAppLockPasswordService(), delay: .fifteenMinutes)
        await sut.unlock()
        sut.scenePhaseDidChange(to: .background)

        sut.deviceWillLock()

        #expect(!sut.isLocked)
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

    // MARK: - Erasing after failed passwords

    @Test
    func init_erasingAfterFailedPasswords_isOffByDefault() throws {
        let sut = try makeSUT(passwordService: FakeAppLockPasswordService(password: Self.password))

        #expect(!sut.erasesAfterFailedPasswords)
    }

    /// With erasing on, the tenth wrong password in a row erases every vault, and the lock screen simply opens the
    /// fresh, empty one, like a new install. It never says the password was wrong, and drops what was waiting to open
    /// an item from the vault that's gone.
    @Test
    func unlockWithPassword_tenthWrongWithErasingOn_erasesAndOpensTheFreshVault() async throws {
        let clock = FakeAppLockClock()
        let didChangeSettings = Counter()
        let service = FakeAppLockPasswordService(
            password: Self.password,
            erasesAfterFailedPasswords: true,
            wrongAttempts: AppLockPasswordAttemptCounter.eraseThreshold - 1,
            clock: clock,
        )
        let sut = try makeSUT(clock: clock, passwordService: service, didChangeSettings: didChangeSettings)
        clock.advance(by: .seconds(60 * 60))
        var didRun = false
        sut.performWhenUnlocked { didRun = true }
        await sut.unlock()

        await sut.unlock(password: "wrong")

        #expect(sut.state == .unlocked)
        #expect(!sut.isPasswordSet)
        #expect(!sut.erasesAfterFailedPasswords)
        #expect(!didRun)
        #expect(didChangeSettings.count == 1)
        #expect(!service.isPasswordSet)
    }

    @Test
    func unlockWithPassword_tenthWrongWithErasingOff_isJustWrong() async throws {
        let clock = FakeAppLockClock()
        let service = FakeAppLockPasswordService(
            password: Self.password,
            wrongAttempts: AppLockPasswordAttemptCounter.eraseThreshold - 1,
            clock: clock,
        )
        let sut = try makeSUT(clock: clock, passwordService: service)
        clock.advance(by: .seconds(60 * 60))
        await sut.unlock()

        await sut.unlock(password: "wrong")

        #expect(sut.state == .locked(.init(
            step: .password,
            failure: .wrongPassword,
            passwordRetryAt: clock.now.advanced(by: .seconds(60 * 60)),
        )))
        #expect(sut.isPasswordSet)
        #expect(service.isPasswordSet)
    }

    /// Any password that opens a vault, the real one or a duress one, unlocks and resets the count, however close it
    /// was to erasing (MANIFESTO.md C2).
    @Test
    func unlockWithPassword_rightAtTheLastAttemptWithErasingOn_unlocksWithoutErasing() async throws {
        let clock = FakeAppLockClock()
        let service = FakeAppLockPasswordService(
            password: Self.password,
            erasesAfterFailedPasswords: true,
            wrongAttempts: AppLockPasswordAttemptCounter.eraseThreshold - 1,
            clock: clock,
        )
        let sut = try makeSUT(clock: clock, passwordService: service)
        clock.advance(by: .seconds(60 * 60))
        await sut.unlock()

        await sut.unlock(password: Self.password)

        #expect(sut.state == .unlocked)
        #expect(sut.isPasswordSet)
        #expect(sut.erasesAfterFailedPasswords)
        #expect(try await service.remainingDelay() == .zero)
    }

    /// Ten wrong ones counted already, with erasing on, is an erase that's due: it erases before trying anything, so
    /// even the right password doesn't escape it.
    @Test
    func unlockWithPassword_eraseDue_erasesWhateverIsEntered() async throws {
        let clock = FakeAppLockClock()
        let service = FakeAppLockPasswordService(
            password: Self.password,
            erasesAfterFailedPasswords: true,
            wrongAttempts: AppLockPasswordAttemptCounter.eraseThreshold,
            clock: clock,
        )
        let sut = try makeSUT(clock: clock, passwordService: service)
        clock.advance(by: .seconds(60 * 60))
        await sut.unlock()

        await sut.unlock(password: Self.password)

        #expect(sut.state == .unlocked)
        #expect(!sut.isPasswordSet)
        #expect(!service.isPasswordSet)
    }

    /// The app locks again while the erase is underway. It finishes all the same, and the lock asks for device
    /// authentication only, as there's no password now. Nothing that was waiting to open an item runs.
    @Test
    func unlockWithPassword_eraseFinishingAfterTheAppLockedAgain_forgetsWhatWasWaiting() async throws {
        let clock = FakeAppLockClock()
        let service = FakeAppLockPasswordService(
            password: Self.password,
            erasesAfterFailedPasswords: true,
            wrongAttempts: AppLockPasswordAttemptCounter.eraseThreshold - 1,
            deadline: .seconds(1),
            clock: clock,
        )
        let sut = try makeSUT(clock: clock, passwordService: service)
        clock.advance(by: .seconds(60 * 60))
        await sut.unlock()
        var didRun = false
        sut.performWhenUnlocked { didRun = true }
        let attempt = Task { await sut.unlock(password: "wrong") }
        while sut.state != .locked(AppLockedState(step: .password, isInProgress: true)) {
            await Task.yield()
        }

        sut.scenePhaseDidChange(to: .background)
        await attempt.value

        #expect(sut.isLocked)
        #expect(!sut.isPasswordSet)
        #expect(!service.isPasswordSet)
        await sut.unlock()
        #expect(sut.state == .unlocked)
        #expect(!didRun)
    }

    @Test
    func setErasesAfterFailedPasswords_rightPassword_turnsItOnThenOff() async throws {
        let service = FakeAppLockPasswordService(password: Self.password)
        let sut = try await makeUnlockedSUT(passwordService: service)

        #expect(try await sut.setErasesAfterFailedPasswords(true, current: Self.password) == .accepted)
        #expect(sut.erasesAfterFailedPasswords)

        #expect(try await sut.setErasesAfterFailedPasswords(false, current: Self.password) == .accepted)
        #expect(!sut.erasesAfterFailedPasswords)
    }

    /// A wrong password counts and waits, as it does for changing the password, but never erases from Settings: the
    /// vault is open.
    @Test
    func setErasesAfterFailedPasswords_wrongPasswords_countWaitAndNeverErase() async throws {
        let clock = FakeAppLockClock()
        let service = FakeAppLockPasswordService(
            password: Self.password,
            erasesAfterFailedPasswords: true,
            clock: clock,
        )
        let sut = try await makeUnlockedSUT(passwordService: service, clock: clock)

        for _ in 1 ..< AppLockPasswordAttemptCounter.eraseThreshold {
            let result = try await sut.setErasesAfterFailedPasswords(false, current: "wrong")
            #expect(result == .wrong)
            clock.advance(by: .seconds(60 * 60))
        }

        #expect(sut.erasesAfterFailedPasswords)
        #expect(sut.isPasswordSet)
        #expect(sut.state == .unlocked)
    }

    /// Settings never tries the attempt that would make the tenth in a row, even to turn erasing on: that one is only
    /// tried at the lock screen.
    @Test
    func setErasesAfterFailedPasswords_tenthAttempt_isOnlyAtTheLockScreen() async throws {
        let clock = FakeAppLockClock()
        let service = FakeAppLockPasswordService(password: Self.password, clock: clock)
        let sut = try await makeUnlockedSUT(passwordService: service, clock: clock)
        for _ in 1 ..< AppLockPasswordAttemptCounter.eraseThreshold {
            _ = try await sut.setErasesAfterFailedPasswords(true, current: "wrong")
            clock.advance(by: .seconds(60 * 60))
        }

        let result = try await sut.setErasesAfterFailedPasswords(true, current: Self.password)

        #expect(result == .onlyAtTheLockScreen)
        #expect(!sut.erasesAfterFailedPasswords)
        #expect(sut.state == .unlocked)
    }

    @Test
    func setErasesAfterFailedPasswords_whileWaiting_triesNothing() async throws {
        let clock = FakeAppLockClock()
        let service = FakeAppLockPasswordService(password: Self.password, clock: clock)
        let sut = try await makeUnlockedSUT(passwordService: service, clock: clock)
        for _ in 1 ... 5 {
            _ = try await sut.setErasesAfterFailedPasswords(true, current: "wrong")
        }

        let result = try await sut.setErasesAfterFailedPasswords(true, current: Self.password)

        #expect(result == .delayed(.seconds(60)))
        #expect(!sut.erasesAfterFailedPasswords)
    }

    /// Turning the password off turns erasing off with it: it only means anything with a password.
    @Test
    func turnOffPassword_turnsErasingOffToo() async throws {
        let service = FakeAppLockPasswordService(password: Self.password, erasesAfterFailedPasswords: true)
        let sut = try await makeUnlockedSUT(passwordService: service)

        _ = try await sut.turnOffPassword(current: Self.password)

        #expect(!sut.erasesAfterFailedPasswords)
        #expect(!service.erasesAfterFailedPasswords)
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

    // MARK: - Setting a duress password

    @Test
    func makeDuressVault_authenticated_makesOneAndChangesNothingTheLockKnows() async throws {
        let didChangeSettings = Counter()
        let service = FakeAppLockPasswordService(password: Self.password)
        let sut = try await makeUnlockedSUT(passwordService: service, didChangeSettings: didChangeSettings)

        let didMake = try await sut.makeDuressVault(password: "plausible decoy")

        #expect(didMake)
        #expect(sut.isPasswordSet)
        #expect(!sut.isChangingSettings)
        #expect(didChangeSettings.count == .zero)
        #expect(try await service.unlock(password: "plausible decoy") == .accepted)
    }

    @Test
    func makeDuressVault_notAuthenticated_makesNothing() async throws {
        let policy = DeviceAuthenticationPolicyMock(
            canAuthenicateWithPasscode: true,
            canAuthenticateWithBiometrics: true,
        )
        // Unlocks the app, then isn't passed for the duress password.
        policy.authenticateWithBiometricsHandler = { reason in reason == "Unlock Vault" }
        let service = FakeAppLockPasswordService(password: Self.password)
        let sut = try makeSUT(policy: policy, passwordService: service)
        await sut.unlock()
        await sut.unlock(password: Self.password)

        let didMake = try await sut.makeDuressVault(password: "plausible decoy")

        #expect(!didMake)
        #expect(policy.authenticateWithBiometricsCallCount == 2)
        #expect(try await service.unlock(password: "plausible decoy") == .wrong)
    }

    @Test
    func makeDuressVault_theAppLockPassword_isRefused() async throws {
        let sut = try await makeUnlockedSUT(passwordService: FakeAppLockPasswordService(password: Self.password))

        await #expect(throws: VaultDuressVaultError.matchesAppLockPassword) {
            try await sut.makeDuressVault(password: Self.password)
        }
        #expect(!sut.isChangingSettings)
    }

    /// It isn't an attempt at the password, so it neither counts nor waits.
    @Test
    func makeDuressVault_whileWaitingAfterWrongPasswords_isNotCountedOrDelayed() async throws {
        let clock = FakeAppLockClock()
        let service = FakeAppLockPasswordService(password: Self.password, clock: clock)
        let sut = try await makeUnlockedSUT(passwordService: service, clock: clock)
        for _ in 1 ... 5 {
            _ = try await sut.changePassword(current: "wrong", new: "battery staple")
        }
        let retryAt = await sut.passwordRetryTime()

        let didMake = try await sut.makeDuressVault(password: "plausible decoy")

        #expect(didMake)
        #expect(await sut.passwordRetryTime() == retryAt)
    }

    @Test
    func makeDuressVault_fails_throwsAndMakesNothing() async throws {
        let service = FakeAppLockPasswordService(password: Self.password)
        let sut = try await makeUnlockedSUT(passwordService: service)
        service.failure = TestError()

        await #expect(throws: TestError.self) {
            try await sut.makeDuressVault(password: "plausible decoy")
        }
        #expect(!sut.isChangingSettings)
        service.failure = nil
        #expect(try await service.unlock(password: "plausible decoy") == .wrong)
    }

    @Test
    func makeDuressVault_noPasswordSet_throws() async throws {
        let sut = try makeSUT(isEnabled: false, passwordService: FakeAppLockPasswordService())

        await #expect(throws: AppLockPasswordUnavailableError.self) {
            try await sut.makeDuressVault(password: "plausible decoy")
        }
    }

    @Test
    func makeDuressVault_whileLocked_throws() async throws {
        let sut = try makeSUT(passwordService: FakeAppLockPasswordService(password: Self.password))

        await #expect(throws: AppLockPasswordUnavailableError.self) {
            try await sut.makeDuressVault(password: "plausible decoy")
        }
    }

    /// In a duress vault, only the duress vault's own password is refused: the real one is accepted like any other.
    @Test
    func makeDuressVault_inADuressVault_refusesOnlyItsOwnPassword() async throws {
        let service = FakeAppLockPasswordService(password: Self.password)
        try await service.makeDuressVault(password: "plausible decoy")
        let sut = try makeSUT(passwordService: service)
        await sut.unlock()
        await sut.unlock(password: "plausible decoy")
        #expect(sut.state == .unlocked)

        await #expect(throws: VaultDuressVaultError.matchesAppLockPassword) {
            try await sut.makeDuressVault(password: "plausible decoy")
        }
        let didMake = try await sut.makeDuressVault(password: Self.password)

        #expect(didMake)
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
        delay: AppLockDelay = .immediately,
    ) throws -> AppLockService {
        let settings = try AppLockSettingsStore(userDefaults: .nonPersistent())
        settings.isEnabled = isEnabled
        settings.delay = delay
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
        delay: AppLockDelay = .immediately,
    ) async throws -> AppLockService {
        let sut = try makeSUT(
            clock: clock,
            passwordService: passwordService,
            didChangeSettings: didChangeSettings,
            delay: delay,
        )
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

/// A value an action on the main actor sets.
@MainActor
private final class BoolBox {
    var value: Bool?
}
