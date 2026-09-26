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
    /// authenticate, the page stays locked.
    @Test
    func authenticate_deniedIfDeviceCannotAuthenticate() async {
        let sut = makeSUT(policy: DeviceAuthenticationPolicyCannotAuthenticate())

        await sut.authenticate()

        #expect(sut.permissionState == .denied)
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

    private func biometricsPolicy(authenticates: Bool) -> DeviceAuthenticationPolicyMock {
        let policy = DeviceAuthenticationPolicyMock(
            canAuthenicateWithPasscode: false,
            canAuthenticateWithBiometrics: true,
        )
        policy.authenticateWithBiometricsHandler = { _ in authenticates }
        return policy
    }
}
