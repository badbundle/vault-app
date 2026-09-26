import Foundation
import Testing
@testable import VaultFeed

@MainActor
struct SettingsDangerViewModelTests {
    @Test
    func init_startsOnOverview() {
        let sut = makeSUT()

        #expect(sut.state == .overview)
        #expect(!sut.isShowingConfirmation)
        #expect(!sut.isDeleting)
    }

    @Test
    func askToConfirm_showsConfirmation() {
        let sut = makeSUT()

        sut.askToConfirm()

        #expect(sut.state == .confirming)
        #expect(sut.isShowingConfirmation)
    }

    @Test
    func cancelConfirmation_returnsToOverview() {
        let sut = makeSUT()
        sut.askToConfirm()

        sut.cancelConfirmation()

        #expect(sut.state == .overview)
    }

    @Test
    func deleteEntireVault_withoutConfirmingFirst_doesNothing() async {
        let deleter = VaultStoreDeleterMock()
        let autofillStore = VaultOTPAutofillStoreMock()
        let policy = DeviceAuthenticationPolicyMock()
        let sut = makeSUT(deleter: deleter, autofillStore: autofillStore, policy: policy)

        await sut.deleteEntireVault()

        #expect(sut.state == .overview)
        #expect(policy.authenticateWithBiometricsCallCount == 0)
        #expect(policy.authenticateWithPasscodeCallCount == 0)
        #expect(deleter.deleteVaultCallCount == 0)
        #expect(autofillStore.removeAllCallCount == 0)
    }

    @Test
    func deleteEntireVault_success_callsDeleterAndClearsAutofillStore() async throws {
        let deleter = VaultStoreDeleterMock()
        let autofillStore = VaultOTPAutofillStoreMock()
        let sut = makeSUT(deleter: deleter, autofillStore: autofillStore)
        sut.askToConfirm()

        let deletion = Task { await sut.deleteEntireVault() }
        // The deliberate 2-second completion delay keeps the operation
        // in flight long enough to observe the loading state.
        while sut.isDeleting == false {
            await Task.yield()
        }
        #expect(sut.isShowingConfirmation)
        await deletion.value

        #expect(deleter.deleteVaultCallCount == 1)
        #expect(autofillStore.removeAllCallCount == 1)
        #expect(sut.state == .deleted)
    }

    @Test
    func deleteEntireVault_deleterFailure_failsWithoutClearingAutofillStore() async {
        let deleter = VaultStoreDeleterMock()
        deleter.deleteVaultHandler = { throw TestError() }
        let autofillStore = VaultOTPAutofillStoreMock()
        let sut = makeSUT(deleter: deleter, autofillStore: autofillStore)
        sut.askToConfirm()

        await sut.deleteEntireVault()

        #expect(sut.state.failure?.userTitle == "Can't delete Vault")
        #expect(sut.isShowingConfirmation)
        #expect(autofillStore.removeAllCallCount == 0)
    }

    @Test
    func deleteEntireVault_requiresAuthenticationBeforeDeleting() async {
        let deleter = VaultStoreDeleterMock()
        let sut = makeSUT(
            deleter: deleter,
            policy: DeviceAuthenticationPolicyAlwaysDeny(),
        )
        sut.askToConfirm()

        await sut.deleteEntireVault()

        // MANIFESTO C4: device auth gates the unattended-device threat
        // for this destructive action; the deleter must never run when
        // it fails.
        #expect(deleter.deleteVaultCallCount == 0)
        #expect(sut.state.failure?.userTitle == "Nothing was deleted")
    }

    @Test
    func deleteEntireVault_afterFailure_canTryAgain() async {
        let deleter = VaultStoreDeleterMock()
        deleter.deleteVaultHandler = { throw TestError() }
        let sut = makeSUT(deleter: deleter)
        sut.askToConfirm()
        await sut.deleteEntireVault()

        deleter.deleteVaultHandler = {}
        await sut.deleteEntireVault()

        #expect(deleter.deleteVaultCallCount == 2)
        #expect(sut.state == .deleted)
    }

    @Test
    func cancelConfirmation_afterFailure_returnsToOverview() async {
        let sut = makeSUT(policy: DeviceAuthenticationPolicyAlwaysDeny())
        sut.askToConfirm()
        await sut.deleteEntireVault()

        sut.cancelConfirmation()

        #expect(sut.state == .overview)
    }

    @Test
    func cancelConfirmation_whileDeleting_keepsDeleting() async {
        let sut = makeSUT()
        sut.askToConfirm()

        let deletion = Task { await sut.deleteEntireVault() }
        while sut.isDeleting == false {
            await Task.yield()
        }
        sut.cancelConfirmation()

        #expect(sut.isDeleting)
        await deletion.value
        #expect(sut.state == .deleted)
    }
}

// MARK: - Helpers

extension SettingsDangerViewModelTests {
    private func makeSUT(
        deleter: VaultStoreDeleterMock = VaultStoreDeleterMock(),
        autofillStore: VaultOTPAutofillStoreMock = VaultOTPAutofillStoreMock(),
        policy: some DeviceAuthenticationPolicy = DeviceAuthenticationPolicyAlwaysAllow(),
    ) -> SettingsDangerViewModel {
        SettingsDangerViewModel(
            dataModel: anyVaultDataModel(
                vaultDeleter: deleter,
                vaultOtpAutofillStore: autofillStore,
            ),
            authenticationService: DeviceAuthenticationService(policy: policy),
        )
    }
}

extension SettingsDangerViewModel.State {
    fileprivate var failure: PresentationError? {
        if case let .failed(error) = self {
            error
        } else {
            nil
        }
    }
}
