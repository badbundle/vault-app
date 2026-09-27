import AuthenticationServices
import Foundation
import FoundationExtensions
import Testing
@testable import VaultFeed

/// Checked against the real `VaultOTPAutofillStoreImpl`, so what reaches the system's identity store is what's counted.
struct PasswordlessOTPAutofillStoreTests {
    // MARK: - Vault that opens without the password

    @Test
    func sync_noPasswordNeeded_savesTheIdentity() async throws {
        let (sut, identityStore, _) = makeSUT(opensWithoutPassword: true)

        try await syncOne(with: sut)

        #expect(identityStore.saveCredentialIdentitiesCallCount == 1)
    }

    @Test
    func syncAll_noPasswordNeeded_replacesTheIdentities() async throws {
        let (sut, identityStore, _) = makeSUT(opensWithoutPassword: true)

        try await sut.syncAll(items: [uniqueVaultItem()])

        #expect(identityStore.removeAllCredentialIdentitiesCallCount == 1)
        #expect(identityStore.saveCredentialIdentitiesCallCount == 1)
    }

    // MARK: - Vault that needs the password

    @Test
    func sync_passwordNeeded_writesNothing() async throws {
        let (sut, identityStore, _) = makeSUT(opensWithoutPassword: false)

        try await syncOne(with: sut)

        #expect(identityStore.saveCredentialIdentitiesCallCount == 0)
        #expect(identityStore.removeCredentialIdentitiesCallCount == 0)
    }

    @Test
    func syncAll_passwordNeeded_emptiesTheStoreAndSavesNothing() async throws {
        let (sut, identityStore, _) = makeSUT(opensWithoutPassword: false)

        try await sut.syncAll(items: [uniqueVaultItem()])

        #expect(identityStore.removeAllCredentialIdentitiesCallCount == 1)
        #expect(identityStore.saveCredentialIdentitiesCallCount == 0)
    }

    @Test
    func removing_passwordNeeded_stillRemoves() async throws {
        let (sut, identityStore, _) = makeSUT(opensWithoutPassword: false)

        try await sut.remove(id: UUID(), code: nil)
        try await sut.removeAll()

        #expect(identityStore.removeCredentialIdentitiesCallCount == 1)
        #expect(identityStore.removeAllCredentialIdentitiesCallCount == 1)
    }

    /// The password can be turned on while the app runs, so the mode is asked before every write.
    @Test
    func sync_passwordTurnedOnWhileRunning_stopsWriting() async throws {
        let (sut, identityStore, opensWithoutPassword) = makeSUT(opensWithoutPassword: true)
        try await syncOne(with: sut)

        opensWithoutPassword.modify { $0 = false }
        try await syncOne(with: sut)

        #expect(identityStore.saveCredentialIdentitiesCallCount == 1)
    }

    /// The password came on while a write was underway, after the app had emptied the store for it: what was written
    /// doesn't stay.
    @Test
    func sync_passwordTurnedOnWhileWriting_emptiesTheStoreAgain() async throws {
        let (sut, identityStore, opensWithoutPassword) = makeSUT(opensWithoutPassword: true)
        identityStore.saveCredentialIdentitiesHandler = { _ in
            opensWithoutPassword.modify { $0 = false }
        }

        try await syncOne(with: sut)

        #expect(identityStore.saveCredentialIdentitiesCallCount == 1)
        #expect(identityStore.removeAllCredentialIdentitiesCallCount == 1)
    }

    @Test
    func syncAll_passwordTurnedOnWhileWriting_emptiesTheStoreAgain() async throws {
        let (sut, identityStore, opensWithoutPassword) = makeSUT(opensWithoutPassword: true)
        identityStore.saveCredentialIdentitiesHandler = { _ in
            opensWithoutPassword.modify { $0 = false }
        }

        try await sut.syncAll(items: [uniqueVaultItem()])

        // Once to replace what was there, and once more since the password came on.
        #expect(identityStore.removeAllCredentialIdentitiesCallCount == 2)
    }

    @Test
    func sync_passwordStillOff_leavesWhatItWrote() async throws {
        let (sut, identityStore, _) = makeSUT(opensWithoutPassword: true)

        try await syncOne(with: sut)
        try await sut.syncAll(items: [uniqueVaultItem()])

        #expect(identityStore.removeAllCredentialIdentitiesCallCount == 1)
    }
}

// MARK: - Helpers

extension PasswordlessOTPAutofillStoreTests {
    private func makeSUT(
        opensWithoutPassword: Bool,
    ) -> (PasswordlessOTPAutofillStore, CredentialIdentityStoreMock, SharedMutex<Bool>) {
        let identityStore = CredentialIdentityStoreMock()
        let isPlain = SharedMutex(opensWithoutPassword)
        let sut = PasswordlessOTPAutofillStore(
            base: VaultOTPAutofillStoreImpl(store: identityStore),
            opensWithoutPassword: { isPlain.value },
        )
        return (sut, identityStore, isPlain)
    }

    private func syncOne(with sut: PasswordlessOTPAutofillStore) async throws {
        try await sut.sync(
            id: UUID(),
            item: .otpCode(anyOTPAuthCode()),
            visibility: .always,
            searchableLevel: .full,
            showInQuickType: true,
        )
    }
}
