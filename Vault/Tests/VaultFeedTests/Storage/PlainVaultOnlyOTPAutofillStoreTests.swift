import AuthenticationServices
import Foundation
import FoundationExtensions
import Testing
@testable import VaultFeed

/// Checked against the real `VaultOTPAutofillStoreImpl`, so what reaches the system's identity store is what's counted.
struct PlainVaultOnlyOTPAutofillStoreTests {
    // MARK: - Plain vault

    @Test
    func sync_plainVault_savesTheIdentity() async throws {
        let (sut, identityStore, _) = makeSUT(isVaultPlain: true)

        try await syncOne(with: sut)

        #expect(identityStore.saveCredentialIdentitiesCallCount == 1)
    }

    @Test
    func syncAll_plainVault_replacesTheIdentities() async throws {
        let (sut, identityStore, _) = makeSUT(isVaultPlain: true)

        try await sut.syncAll(items: [uniqueVaultItem()])

        #expect(identityStore.removeAllCredentialIdentitiesCallCount == 1)
        #expect(identityStore.saveCredentialIdentitiesCallCount == 1)
    }

    // MARK: - Encrypted vault

    @Test
    func sync_encryptedVault_writesNothing() async throws {
        let (sut, identityStore, _) = makeSUT(isVaultPlain: false)

        try await syncOne(with: sut)

        #expect(identityStore.saveCredentialIdentitiesCallCount == 0)
        #expect(identityStore.removeCredentialIdentitiesCallCount == 0)
    }

    @Test
    func syncAll_encryptedVault_emptiesTheStoreAndSavesNothing() async throws {
        let (sut, identityStore, _) = makeSUT(isVaultPlain: false)

        try await sut.syncAll(items: [uniqueVaultItem()])

        #expect(identityStore.removeAllCredentialIdentitiesCallCount == 1)
        #expect(identityStore.saveCredentialIdentitiesCallCount == 0)
    }

    @Test
    func removing_encryptedVault_stillRemoves() async throws {
        let (sut, identityStore, _) = makeSUT(isVaultPlain: false)

        try await sut.remove(id: UUID(), code: nil)
        try await sut.removeAll()

        #expect(identityStore.removeCredentialIdentitiesCallCount == 1)
        #expect(identityStore.removeAllCredentialIdentitiesCallCount == 1)
    }

    /// The password can be turned on while the app runs, so the mode is asked before every write.
    @Test
    func sync_vaultEncryptedWhileRunning_stopsWriting() async throws {
        let (sut, identityStore, isVaultPlain) = makeSUT(isVaultPlain: true)
        try await syncOne(with: sut)

        isVaultPlain.modify { $0 = false }
        try await syncOne(with: sut)

        #expect(identityStore.saveCredentialIdentitiesCallCount == 1)
    }
}

// MARK: - Helpers

extension PlainVaultOnlyOTPAutofillStoreTests {
    private func makeSUT(
        isVaultPlain: Bool,
    ) -> (PlainVaultOnlyOTPAutofillStore, CredentialIdentityStoreMock, SharedMutex<Bool>) {
        let identityStore = CredentialIdentityStoreMock()
        let isPlain = SharedMutex(isVaultPlain)
        let sut = PlainVaultOnlyOTPAutofillStore(
            base: VaultOTPAutofillStoreImpl(store: identityStore),
            isVaultPlain: { isPlain.value },
        )
        return (sut, identityStore, isPlain)
    }

    private func syncOne(with sut: PlainVaultOnlyOTPAutofillStore) async throws {
        try await sut.sync(
            id: UUID(),
            item: .otpCode(anyOTPAuthCode()),
            visibility: .always,
            searchableLevel: .full,
            showInQuickType: true,
        )
    }
}
