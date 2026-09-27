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

    // MARK: - Setting a duress password

    private static let duressPassword = "plausible decoy"

    @Test
    func setDuress_asksForANewPasswordOnly() async throws {
        let (sut, _, _) = try await makeSUT(purpose: .setDuress)

        #expect(!sut.needsCurrentPassword)
        #expect(sut.needsNewPassword)
    }

    @Test(arguments: weakPasswords)
    func setDuress_weakPassword_cannotBeSubmitted(
        password: String,
        problem: AppLockPasswordRules.Problem,
    ) async throws {
        let (sut, _, _) = try await makeSUT(purpose: .setDuress)

        sut.newPassword = password
        sut.confirmation = password

        #expect(sut.newPasswordProblem == problem)
        #expect(!sut.canSubmit)
    }

    @Test
    func setDuress_confirmationDoesNotMatch_cannotBeSubmitted() async throws {
        let (sut, _, _) = try await makeSUT(purpose: .setDuress)

        sut.newPassword = Self.duressPassword
        sut.confirmation = Self.duressPassword + "!"

        #expect(sut.newPasswordProblem == nil)
        #expect(!sut.confirmationMatches)
        #expect(!sut.canSubmit)
    }

    /// The form leaves comparing it with the App Lock Password to the password service, so it can be submitted.
    @Test
    func setDuress_appLockPassword_canBeSubmitted() async throws {
        let (sut, _, _) = try await makeSUT(purpose: .setDuress)

        sut.newPassword = Self.password
        sut.confirmation = Self.password

        #expect(!sut.isNewPasswordSameAsCurrent)
        #expect(sut.canSubmit)
    }

    @Test
    func submit_setDuress_makesAVaultThePasswordOpens() async throws {
        let (sut, service, _) = try await makeSUT(purpose: .setDuress)
        sut.newPassword = Self.duressPassword
        sut.confirmation = Self.duressPassword

        await sut.submit()

        #expect(sut.state == .done)
        #expect(sut.newPassword.isEmpty)
        #expect(sut.confirmation.isEmpty)
        #expect(try await service.unlock(password: Self.duressPassword) == .accepted)
        #expect(try await service.unlock(password: Self.password) == .accepted)
    }

    @Test
    func submit_setDuress_again_replacesTheLastVault() async throws {
        let (first, service, appLock) = try await makeSUT(purpose: .setDuress)
        await submitDuressPassword("first decoy", with: first)
        let second = AppLockPasswordFormViewModel(purpose: .setDuress, appLock: appLock)

        await submitDuressPassword("second decoy", with: second)

        #expect(second.state == .done)
        #expect(try await service.unlock(password: "first decoy") == .wrong)
        #expect(try await service.unlock(password: "second decoy") == .accepted)
    }

    @Test
    func submit_setDuress_appLockPassword_isRefusedAndForgotten() async throws {
        let (sut, service, _) = try await makeSUT(purpose: .setDuress)
        sut.newPassword = Self.password
        sut.confirmation = Self.password

        await sut.submit()

        #expect(sut.state == .editing)
        #expect(sut.isNewPasswordRefused)
        #expect(sut.refusedPasswordCount == 1)
        #expect(sut.newPassword.isEmpty)
        #expect(sut.confirmation.isEmpty)
        #expect(!sut.canSubmit)
        #expect(try await service.unlock(password: Self.password) == .accepted)
    }

    @Test
    func setDuress_refused_isForgottenOnceAnotherIsTyped() async throws {
        let (sut, _, _) = try await makeSUT(purpose: .setDuress)
        await submitDuressPassword(Self.password, with: sut)

        sut.newPassword = "p"

        #expect(!sut.isNewPasswordRefused)
        #expect(sut.refusedPasswordCount == 1)
    }

    @Test
    func submit_setDuress_refused_isNotAWrongAttempt() async throws {
        let clock = FakeAppLockClock()
        let (sut, _, appLock) = try await makeSUT(purpose: .setDuress, clock: clock)

        for _ in 1 ... 6 {
            await submitDuressPassword(Self.password, with: sut)
        }

        #expect(sut.refusedPasswordCount == 6)
        #expect(sut.wrongPasswordCount == 0)
        #expect(!sut.isCurrentPasswordWrong)
        #expect(await appLock.passwordRetryTime() == nil)
    }

    @Test
    func submit_setDuress_notAuthenticated_keepsEditingAndMakesNothing() async throws {
        let service = FakeAppLockPasswordService(password: Self.password)
        let policy = DeviceAuthenticationPolicyMock(
            canAuthenicateWithPasscode: true,
            canAuthenticateWithBiometrics: true,
        )
        // Unlocks the app, then isn't passed for the duress password.
        policy.authenticateWithBiometricsHandler = { reason in reason == "Unlock Vault" }
        let appLock = try makeAppLock(policy: policy, service: service, clock: FakeAppLockClock())
        await appLock.unlock()
        await appLock.unlock(password: Self.password)
        let sut = AppLockPasswordFormViewModel(purpose: .setDuress, appLock: appLock)

        await submitDuressPassword(Self.duressPassword, with: sut)

        #expect(sut.state == .editing)
        #expect(!sut.isNewPasswordRefused)
        #expect(sut.newPassword == Self.duressPassword)
        #expect(try await service.unlock(password: Self.duressPassword) == .wrong)
    }

    @Test
    func submit_setDuress_fails_saysSoAndForgetsWhatWasTyped() async throws {
        let (sut, service, _) = try await makeSUT(purpose: .setDuress)
        service.failure = TestError()

        await submitDuressPassword(Self.duressPassword, with: sut)

        #expect(sut.state == .failed)
        #expect(!sut.isNewPasswordRefused)
        #expect(sut.newPassword.isEmpty)
        #expect(sut.confirmation.isEmpty)
    }

    // MARK: - Setting a duress password: no sign one exists

    /// Nothing on the screen, before or after, depends on whether a duress vault was made before.
    @Test
    func setDuress_looksTheSameWhetherOrNotOneWasMade() async throws {
        let (fresh, _, _) = try await makeSUT(purpose: .setDuress)
        let (replacing, service, _) = try await makeSUT(purpose: .setDuress)
        try await service.makeDuressVault(password: "earlier decoy")

        #expect(Screen(fresh) == Screen(replacing))

        await submitDuressPassword(Self.duressPassword, with: fresh)
        await submitDuressPassword(Self.duressPassword, with: replacing)

        #expect(fresh.state == .done)
        #expect(Screen(fresh) == Screen(replacing))
    }

    /// Inside a duress vault, it's the same screen, and it refuses and accepts by the same rule: only the open
    /// vault's own password is refused.
    @Test
    func setDuress_looksTheSameInADuressVault() async throws {
        let (real, _, _) = try await makeSUT(purpose: .setDuress)
        let (inDuress, _, _) = try await makeSUTInADuressVault(purpose: .setDuress)

        #expect(Screen(real) == Screen(inDuress))

        await submitDuressPassword(Self.password, with: real)
        await submitDuressPassword(Self.duressPassword, with: inDuress)

        #expect(real.isNewPasswordRefused)
        #expect(Screen(real) == Screen(inDuress))

        await submitDuressPassword("nested decoy", with: real)
        await submitDuressPassword("nested decoy", with: inDuress)

        #expect(real.state == .done)
        #expect(Screen(real) == Screen(inDuress))
    }

    /// Refusing a password that opens another vault would say that vault exists.
    @Test
    func submit_setDuress_inADuressVault_realPasswordIsAcceptedWithoutAWord() async throws {
        let (sut, _, _) = try await makeSUTInADuressVault(purpose: .setDuress)

        await submitDuressPassword(Self.password, with: sut)

        #expect(sut.state == .done)
        #expect(!sut.isNewPasswordRefused)
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

    /// A form in a duress vault: unlocked with the duress password, as Settings would be.
    private func makeSUTInADuressVault(
        purpose: AppLockPasswordFormViewModel.Purpose,
    ) async throws -> (AppLockPasswordFormViewModel, FakeAppLockPasswordService, AppLockService) {
        let service = FakeAppLockPasswordService(password: Self.password)
        try await service.makeDuressVault(password: Self.duressPassword)
        let appLock = try makeAppLock(policy: .alwaysAllow, service: service, clock: FakeAppLockClock())
        await appLock.unlock()
        await appLock.unlock(password: Self.duressPassword)
        #expect(appLock.state == .unlocked)
        return (AppLockPasswordFormViewModel(purpose: purpose, appLock: appLock), service, appLock)
    }

    private func submitDuressPassword(_ password: String, with viewModel: AppLockPasswordFormViewModel) async {
        viewModel.newPassword = password
        viewModel.confirmation = password
        await viewModel.submit()
    }

    /// Everything the form shows.
    private struct Screen: Equatable {
        var state: AppLockPasswordFormViewModel.State
        var needsCurrentPassword: Bool
        var needsNewPassword: Bool
        var newPasswordProblem: AppLockPasswordRules.Problem?
        var confirmationMatches: Bool
        var canSubmit: Bool
        var isNewPasswordRefused: Bool
        var refusedPasswordCount: Int
        var isCurrentPasswordWrong: Bool
        var wrongPasswordCount: Int
        var isWaiting: Bool

        @MainActor
        init(_ viewModel: AppLockPasswordFormViewModel) {
            state = viewModel.state
            needsCurrentPassword = viewModel.needsCurrentPassword
            needsNewPassword = viewModel.needsNewPassword
            newPasswordProblem = viewModel.newPasswordProblem
            confirmationMatches = viewModel.confirmationMatches
            canSubmit = viewModel.canSubmit
            isNewPasswordRefused = viewModel.isNewPasswordRefused
            refusedPasswordCount = viewModel.refusedPasswordCount
            isCurrentPasswordWrong = viewModel.isCurrentPasswordWrong
            wrongPasswordCount = viewModel.wrongPasswordCount
            isWaiting = viewModel.retryAt != nil
        }
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
