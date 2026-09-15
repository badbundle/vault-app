import Foundation
import Testing
@testable import VaultFeed

@MainActor
struct SettingsDangerViewModelTests {
    @Test
    func deleteEntireVault_success_callsDeleterAndClearsAutofillStore() async throws {
        let deleter = VaultStoreDeleterMock()
        let autofillStore = VaultOTPAutofillStoreMock()
        let sut = makeSUT(deleter: deleter, autofillStore: autofillStore)

        let deletion = Task { try await sut.deleteEntireVault() }
        // The deliberate 2-second completion delay keeps the operation
        // in flight long enough to observe the loading state.
        while sut.isDeleting == false {
            await Task.yield()
        }
        try await deletion.value

        #expect(deleter.deleteVaultCallCount == 1)
        #expect(autofillStore.removeAllCallCount == 1)
        #expect(sut.isDeleting == false)
    }

    @Test
    func deleteEntireVault_deleterFailure_throwsPresentationErrorAndResetsState() async {
        let deleter = VaultStoreDeleterMock()
        deleter.deleteVaultHandler = { throw TestError() }
        let autofillStore = VaultOTPAutofillStoreMock()
        let sut = makeSUT(deleter: deleter, autofillStore: autofillStore)

        await #expect(throws: PresentationError.self) {
            try await sut.deleteEntireVault()
        }

        #expect(sut.isDeleting == false)
        #expect(autofillStore.removeAllCallCount == 0)
    }

    @Test
    func deleteEntireVault_requiresAuthenticationBeforeDeleting() async {
        let deleter = VaultStoreDeleterMock()
        let sut = makeSUT(
            deleter: deleter,
            policy: DeviceAuthenticationPolicyAlwaysDeny(),
        )

        await #expect(throws: PresentationError.self) {
            try await sut.deleteEntireVault()
        }

        // MANIFESTO C4: device auth gates the unattended-device threat
        // for this destructive action; the deleter must never run when
        // it fails.
        #expect(deleter.deleteVaultCallCount == 0)
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
