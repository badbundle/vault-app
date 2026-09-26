import Foundation
import TestHelpers
import Testing
@testable import VaultFeed

@MainActor
struct AppLockPasswordFormViewModelTests {
    private static let password = "correct horse"
    private static let newPassword = "battery staple"

    // MARK: - Setting

    @Test
    func set_asksForANewPasswordOnly() throws {
        let (sut, _) = try makeSetSUT()

        #expect(!sut.needsCurrentPassword)
        #expect(sut.needsNewPassword)
    }

    private nonisolated static let weakPasswords: [(password: String, problem: AppLockPasswordRules.Problem)] = [
        ("short", .tooShort),
        ("12345678", .onlyNumbers),
    ]

    @Test(arguments: weakPasswords)
    func set_weakPassword_cannotBeSubmitted(password: String, problem: AppLockPasswordRules.Problem) throws {
        let (sut, _) = try makeSetSUT()

        sut.newPassword = password
        sut.confirmation = password

        #expect(sut.newPasswordProblem == problem)
        #expect(!sut.canSubmit)
    }

    @Test
    func set_confirmationDoesNotMatch_cannotBeSubmitted() throws {
        let (sut, _) = try makeSetSUT()

        sut.newPassword = Self.password
        sut.confirmation = Self.password + "!"

        #expect(sut.newPasswordProblem == nil)
        #expect(!sut.confirmationMatches)
        #expect(!sut.canSubmit)
    }

    @Test
    func set_nothingTyped_saysNothingIsWrongYet() throws {
        let (sut, _) = try makeSetSUT()

        #expect(sut.newPasswordProblem == nil)
        #expect(!sut.canSubmit)
    }

    @Test
    func submit_set_setsThePasswordAndForgetsWhatWasTyped() async throws {
        let (sut, appLock) = try makeSetSUT()
        sut.newPassword = Self.password
        sut.confirmation = Self.password

        await sut.submit()

        #expect(sut.state == .done)
        #expect(appLock.isPasswordSet)
        #expect(sut.newPassword.isEmpty)
        #expect(sut.confirmation.isEmpty)
    }

    @Test
    func submit_set_notAuthenticated_keepsEditing() async throws {
        let (sut, appLock) = try makeSetSUT(policy: .alwaysDeny)
        sut.newPassword = Self.password
        sut.confirmation = Self.password

        await sut.submit()

        #expect(sut.state == .editing)
        #expect(!appLock.isPasswordSet)
        #expect(sut.newPassword == Self.password)
    }

    @Test
    func submit_set_fails_saysSoAndForgetsWhatWasTyped() async throws {
        let service = FakeAppLockPasswordService()
        service.failure = TestError()
        let (sut, appLock) = try makeSetSUT(service: service)
        sut.newPassword = Self.password
        sut.confirmation = Self.password

        await sut.submit()

        #expect(sut.state == .failed)
        #expect(!appLock.isPasswordSet)
        #expect(sut.newPassword.isEmpty)
        #expect(sut.canSubmit == false)
    }

    // MARK: - Changing

    @Test
    func change_asksForTheCurrentAndANewPassword() async throws {
        let (sut, _, _) = try await makeSUT(purpose: .change)

        #expect(sut.needsCurrentPassword)
        #expect(sut.needsNewPassword)
    }

    @Test
    func change_noCurrentPassword_cannotBeSubmitted() async throws {
        let (sut, _, _) = try await makeSUT(purpose: .change)

        sut.newPassword = Self.newPassword
        sut.confirmation = Self.newPassword

        #expect(!sut.canSubmit)
    }

    @Test
    func change_newPasswordSameAsCurrent_cannotBeSubmitted() async throws {
        let (sut, _, _) = try await makeSUT(purpose: .change)

        sut.currentPassword = Self.password
        sut.newPassword = Self.password
        sut.confirmation = Self.password

        #expect(sut.isNewPasswordSameAsCurrent)
        #expect(!sut.canSubmit)
    }

    @Test
    func submit_change_right_changesThePassword() async throws {
        let (sut, service, _) = try await makeSUT(purpose: .change)
        sut.currentPassword = Self.password
        sut.newPassword = Self.newPassword
        sut.confirmation = Self.newPassword

        await sut.submit()

        #expect(sut.state == .done)
        #expect(sut.currentPassword.isEmpty)
        #expect(sut.newPassword.isEmpty)
        #expect(try await service.unlock(password: Self.newPassword) == .accepted)
    }

    @Test
    func submit_change_wrongCurrentPassword_saysSoAndKeepsTheNewOne() async throws {
        let (sut, service, _) = try await makeSUT(purpose: .change)
        sut.currentPassword = "wrong"
        sut.newPassword = Self.newPassword
        sut.confirmation = Self.newPassword

        await sut.submit()

        #expect(sut.state == .editing)
        #expect(sut.isCurrentPasswordWrong)
        #expect(sut.wrongPasswordCount == 1)
        #expect(sut.currentPassword.isEmpty)
        #expect(sut.newPassword == Self.newPassword)
        #expect(sut.retryAt == nil)
        #expect(try await service.unlock(password: Self.password) == .accepted)
    }

    @Test
    func submit_change_fifthWrongCurrentPassword_waitsAMinute() async throws {
        let clock = FakeAppLockClock()
        let (sut, _, _) = try await makeSUT(purpose: .change, clock: clock)

        for _ in 1 ... 5 {
            sut.currentPassword = "wrong"
            sut.newPassword = Self.newPassword
            sut.confirmation = Self.newPassword
            await sut.submit()
        }

        #expect(sut.wrongPasswordCount == 5)
        #expect(sut.retryAt == clock.now.advanced(by: .seconds(60)))
    }

    @Test
    func submit_change_whileWaiting_isNotCountedAsWrong() async throws {
        let clock = FakeAppLockClock()
        let (sut, _, _) = try await makeSUT(purpose: .change, clock: clock)
        for _ in 1 ... 5 {
            sut.currentPassword = "wrong"
            sut.newPassword = Self.newPassword
            sut.confirmation = Self.newPassword
            await sut.submit()
        }
        clock.advance(by: .seconds(20))

        sut.currentPassword = Self.password
        await sut.submit()

        #expect(sut.state == .editing)
        #expect(sut.wrongPasswordCount == 5)
        #expect(sut.retryAt == clock.now.advanced(by: .seconds(40)))
        #expect(sut.currentPassword.isEmpty)
    }

    @Test
    func onAppear_waitingAfterWrongPasswords_saysUntilWhen() async throws {
        let clock = FakeAppLockClock()
        let (sut, _, appLock) = try await makeSUT(purpose: .turnOff, clock: clock)
        for _ in 1 ... 5 {
            sut.currentPassword = "wrong"
            await sut.submit()
        }
        clock.advance(by: .seconds(15))
        let form = AppLockPasswordFormViewModel(purpose: .change, appLock: appLock)

        await form.onAppear()

        #expect(form.retryAt == clock.now.advanced(by: .seconds(45)))
    }

    // MARK: - Turning off

    @Test
    func turnOff_asksForTheCurrentPasswordOnly() async throws {
        let (sut, _, _) = try await makeSUT(purpose: .turnOff)

        sut.currentPassword = Self.password

        #expect(!sut.needsNewPassword)
        #expect(sut.canSubmit)
    }

    @Test
    func submit_turnOff_right_turnsItOff() async throws {
        let (sut, service, _) = try await makeSUT(purpose: .turnOff)
        sut.currentPassword = Self.password

        await sut.submit()

        #expect(sut.state == .done)
        #expect(!service.isPasswordSet)
    }

    @Test
    func submit_turnOff_wrong_leavesItOn() async throws {
        let (sut, service, _) = try await makeSUT(purpose: .turnOff)
        sut.currentPassword = "wrong"

        await sut.submit()

        #expect(sut.isCurrentPasswordWrong)
        #expect(service.isPasswordSet)
    }

    // MARK: - Leaving

    @Test
    func didDisappear_forgetsWhatWasTyped() async throws {
        let (sut, _, _) = try await makeSUT(purpose: .change)
        sut.currentPassword = Self.password
        sut.newPassword = Self.newPassword
        sut.confirmation = Self.newPassword

        sut.didDisappear()

        #expect(sut.currentPassword.isEmpty)
        #expect(sut.newPassword.isEmpty)
        #expect(sut.confirmation.isEmpty)
    }
}

// MARK: - Helpers

extension AppLockPasswordFormViewModelTests {
    /// A form to set the password, where none is set yet, and the app lock it sets it with.
    private func makeSetSUT(
        policy: any DeviceAuthenticationPolicy = .alwaysAllow,
        service: FakeAppLockPasswordService = FakeAppLockPasswordService(),
    ) throws -> (AppLockPasswordFormViewModel, AppLockService) {
        let appLock = try makeAppLock(policy: policy, service: service, clock: FakeAppLockClock())
        return (AppLockPasswordFormViewModel(purpose: .set, appLock: appLock), appLock)
    }

    /// A form for a password that's set, with the app unlocked, as it is in Settings.
    private func makeSUT(
        purpose: AppLockPasswordFormViewModel.Purpose,
        clock: FakeAppLockClock = FakeAppLockClock(),
    ) async throws -> (AppLockPasswordFormViewModel, FakeAppLockPasswordService, AppLockService) {
        let service = FakeAppLockPasswordService(password: Self.password, clock: clock)
        let appLock = try makeAppLock(policy: .alwaysAllow, service: service, clock: clock)
        await appLock.unlock()
        await appLock.unlock(password: Self.password)
        #expect(appLock.state == .unlocked)
        return (AppLockPasswordFormViewModel(purpose: purpose, appLock: appLock), service, appLock)
    }

    private func makeAppLock(
        policy: any DeviceAuthenticationPolicy,
        service: FakeAppLockPasswordService,
        clock: FakeAppLockClock,
    ) throws -> AppLockService {
        let settings = try AppLockSettingsStore(userDefaults: .nonPersistent())
        return AppLockService(
            settings: settings,
            authenticationService: DeviceAuthenticationService(policy: policy),
            passwordService: service,
            clock: clock,
            purgeSensitiveData: {},
        )
    }
}
