import Foundation
import TestHelpers
import Testing
@testable import VaultFeed

@MainActor
struct BackupRestoreViewModelTests {
    @Test
    func init_isLockedWithoutAskingToAuthenticate() {
        let policy = biometricsPolicy(authenticates: true)
        let sut = makeSUT(policy: policy)

        #expect(sut.permissionState == .undetermined)
        #expect(policy.authenticateWithBiometricsCallCount == 0)
        #expect(policy.authenticateWithPasscodeCallCount == 0)
    }

    @Test
    func authenticate_unlocksIfAuthenticated() async {
        let policy = biometricsPolicy(authenticates: true)
        let sut = makeSUT(policy: policy)

        await sut.authenticate()

        #expect(sut.permissionState == .allowed)
        #expect(policy.authenticateWithBiometricsCallCount == 1)
    }

    @Test
    func authenticate_asksWithReason() async {
        let policy = biometricsPolicy(authenticates: true)
        let sut = makeSUT(policy: policy)

        await sut.authenticate()

        #expect(policy.authenticateWithBiometricsArgValues == ["Authenticate to restore a backup."])
    }

    @Test
    func authenticate_deniedIfNotAuthenticated() async {
        let sut = makeSUT(policy: biometricsPolicy(authenticates: false))

        await sut.authenticate()

        #expect(sut.permissionState == .denied)
    }

    @Test
    func authenticate_deniedIfAuthenticationErrors() async {
        let policy = DeviceAuthenticationPolicyMock(
            canAuthenicateWithPasscode: false,
            canAuthenticateWithBiometrics: true,
        )
        policy.authenticateWithBiometricsHandler = { _ in throw TestError() }
        let sut = makeSUT(policy: policy)

        await sut.authenticate()

        #expect(sut.permissionState == .denied)
    }

    /// Whether or not a backup password is set has nothing to do with it: with no way to
    /// authenticate, the page stays locked, and says a passcode is needed from the start.
    @Test
    func init_withoutAPasscode_isUnavailable() {
        let sut = makeSUT(policy: DeviceAuthenticationPolicyCannotAuthenticate())

        #expect(sut.permissionState == .unavailable)
    }

    @Test
    func authenticate_withoutAPasscode_staysUnavailableWithoutAsking() async {
        let policy = noPasscodePolicy()
        let sut = makeSUT(policy: policy)

        await sut.authenticate()

        #expect(sut.permissionState == .unavailable)
        #expect(policy.authenticateWithBiometricsCallCount == 0)
        #expect(policy.authenticateWithPasscodeCallCount == 0)
    }

    /// The page locks whenever the app goes to the background, so a passcode set up in the
    /// Settings app is noticed on return.
    @Test
    func lock_afterAPasscodeIsSetUp_asksToAuthenticate() async {
        let policy = noPasscodePolicy()
        let sut = makeSUT(policy: policy)

        policy.canAuthenicateWithPasscode = true
        policy.authenticateWithPasscodeHandler = { _ in true }
        sut.lock()

        #expect(sut.permissionState == .undetermined)
        await sut.authenticate()
        #expect(sut.permissionState == .allowed)
    }

    @Test
    func authenticate_unlocksOnRetryAfterFailure() async {
        let policy = biometricsPolicy(authenticates: false)
        let sut = makeSUT(policy: policy)
        await sut.authenticate()

        policy.authenticateWithBiometricsHandler = { _ in true }
        await sut.authenticate()

        #expect(sut.permissionState == .allowed)
    }

    @Test
    func lock_locksUnlockedPage() async {
        let sut = makeSUT(policy: biometricsPolicy(authenticates: true))
        await sut.authenticate()

        sut.lock()

        #expect(sut.permissionState == .undetermined)
    }

    @Test
    func lock_clearsFailure() async {
        let sut = makeSUT(policy: biometricsPolicy(authenticates: false))
        await sut.authenticate()

        sut.lock()

        #expect(sut.permissionState == .undetermined)
    }

    @Test
    func lock_needsAuthenticatingAgainToUnlock() async {
        let policy = biometricsPolicy(authenticates: true)
        let sut = makeSUT(policy: policy)
        await sut.authenticate()
        sut.lock()

        await sut.authenticate()

        #expect(sut.permissionState == .allowed)
        #expect(policy.authenticateWithBiometricsCallCount == 2)
    }
}

// MARK: - Helpers

extension BackupRestoreViewModelTests {
    private func makeSUT(policy: any DeviceAuthenticationPolicy) -> BackupRestoreViewModel {
        BackupRestoreViewModel(authenticationService: DeviceAuthenticationService(policy: policy))
    }

    private func noPasscodePolicy() -> DeviceAuthenticationPolicyMock {
        DeviceAuthenticationPolicyMock(canAuthenicateWithPasscode: false, canAuthenticateWithBiometrics: false)
    }

    private func biometricsPolicy(authenticates: Bool) -> DeviceAuthenticationPolicyMock {
        let policy = DeviceAuthenticationPolicyMock(
            canAuthenicateWithPasscode: false,
            canAuthenticateWithBiometrics: true,
        )
        policy.authenticateWithBiometricsHandler = { _ in authenticates }
        return policy
    }
}
