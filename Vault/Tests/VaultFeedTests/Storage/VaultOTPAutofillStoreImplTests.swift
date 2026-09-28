import AuthenticationServices
import Foundation
import Testing
import VaultCore
@testable import VaultFeed

struct VaultOTPAutofillStoreImplTests {
    @Test(arguments: [
        ("", ""),
        ("tom@me.com", ""),
        ("", "issuer"),
        ("tom@me.com", "issuer"),
        ("tom@me.com", "issuer@example.com"),
    ])
    func sync_otpItem_createsIdentityWithCorrectIdentifiers(accountName: String, issuerName: String) async throws {
        let spy = CredentialIdentityStoreMock()
        let sut = makeSUT(store: spy)
        let id = UUID()
        let code = anyOTPAuthCode(
            accountName: accountName,
            issuerName: issuerName,
        )

        try await sut.sync(
            id: id,
            item: anyItemWrite(.otpCode(code)),
        )

        let identities = try #require(spy.saveCredentialIdentitiesArgValues.first)
        let identity = try #require(identities.first as? ASOneTimeCodeCredentialIdentity)
        #expect(identity.recordIdentifier == id.uuidString)
        #expect(identity.serviceIdentifier.identifier == issuerName)
        #expect(identity.serviceIdentifier.type == .domain)
        #expect(identity.label == accountName)
    }

    @Test
    func sync_otpItem_savesSingleIdentity() async throws {
        let spy = CredentialIdentityStoreMock()
        let sut = makeSUT(store: spy)
        let id = UUID()
        let code = anyOTPAuthCode()

        try await sut.sync(
            id: id,
            item: anyItemWrite(.otpCode(code)),
        )

        #expect(spy.saveCredentialIdentitiesCallCount == 1)
        let identities = try #require(spy.saveCredentialIdentitiesArgValues.first)
        #expect(identities.count == 1)
    }

    @Test
    func sync_otpItem_removesBeforeSaving() async throws {
        let spy = CredentialIdentityStoreMock()
        let sut = makeSUT(store: spy)
        let id = UUID()
        let code = anyOTPAuthCode()

        try await sut.sync(
            id: id,
            item: anyItemWrite(.otpCode(code)),
        )

        // Should remove existing identity first, then save the new one
        // This ensures updates are reflected in the QuickType bar
        #expect(spy.removeCredentialIdentitiesCallCount == 1)
        #expect(spy.saveCredentialIdentitiesCallCount == 1)

        // Verify the remove happened before the save
        let removeIdentities = try #require(spy.removeCredentialIdentitiesArgValues.first)
        let removeIdentity = try #require(removeIdentities.first as? ASOneTimeCodeCredentialIdentity)
        #expect(removeIdentity.recordIdentifier == id.uuidString)
    }

    @Test
    func sync_nonOTPItem_removesFromStore() async throws {
        let spy = CredentialIdentityStoreMock()
        let sut = makeSUT(store: spy)
        let id = UUID()

        try await sut.sync(
            id: id,
            item: anyItemWrite(.secureNote(.init(title: "Note", contents: "Content", format: .plain))),
        )

        #expect(spy.saveCredentialIdentitiesCallCount == 0)
        #expect(spy.removeCredentialIdentitiesCallCount == 1)
        let identities = try #require(spy.removeCredentialIdentitiesArgValues.first)
        let identity = try #require(identities.first as? ASOneTimeCodeCredentialIdentity)
        #expect(identity.recordIdentifier == id.uuidString)
    }

    @Test
    func sync_errorInStoreIsRethrown() async throws {
        let spy = CredentialIdentityStoreMock()
        let sut = makeSUT(store: spy)
        spy.saveCredentialIdentitiesHandler = { _ in
            throw TestError()
        }

        await #expect(throws: (any Error).self) {
            try await sut.sync(
                id: UUID(),
                item: anyItemWrite(.otpCode(anyOTPAuthCode())),
            )
        }
    }

    @Test
    func remove_createsIdentityWithCorrectRecordIdentifier() async throws {
        let spy = CredentialIdentityStoreMock()
        let sut = makeSUT(store: spy)
        let id = UUID()

        try await sut.remove(id: id, code: nil)

        let identities = try #require(spy.removeCredentialIdentitiesArgValues.first)
        let identity = try #require(identities.first as? ASOneTimeCodeCredentialIdentity)
        #expect(identity.recordIdentifier == id.uuidString)
    }

    @Test
    func remove_errorInStoreIsRethrown() async throws {
        let spy = CredentialIdentityStoreMock()
        let sut = makeSUT(store: spy)
        spy.removeCredentialIdentitiesHandler = { _ in
            throw TestError()
        }

        await #expect(throws: (any Error).self) {
            try await sut.remove(id: UUID(), code: nil)
        }
    }

    @Test
    func removeAll_callsStoreRemoveAll() async throws {
        let spy = CredentialIdentityStoreMock()
        let sut = makeSUT(store: spy)

        try await sut.removeAll()

        #expect(spy.removeAllCredentialIdentitiesCallCount == 1)
    }

    @Test
    func removeAll_errorInStoreIsRethrown() async throws {
        let spy = CredentialIdentityStoreMock()
        let sut = makeSUT(store: spy)
        spy.removeAllCredentialIdentitiesHandler = {
            throw TestError()
        }

        await #expect(throws: (any Error).self) {
            try await sut.removeAll()
        }
    }

    @Test
    func syncAll_clearsAndRepopulatesStore() async throws {
        let spy = CredentialIdentityStoreMock()
        let sut = makeSUT(store: spy)

        let item1 = uniqueVaultItem(item: .otpCode(anyOTPAuthCode(accountName: "user1", issuerName: "example.com")))
        let item2 = uniqueVaultItem(item: .otpCode(anyOTPAuthCode(accountName: "user2", issuerName: "test.com")))
        let item3 = uniqueVaultItem(item: .secureNote(.init(title: "Note", contents: "Content", format: .plain)))

        try await sut.syncAll(items: [item1, item2, item3])

        #expect(spy.removeAllCredentialIdentitiesCallCount == 1)
        #expect(spy.saveCredentialIdentitiesCallCount == 1)

        let identities = try #require(spy.saveCredentialIdentitiesArgValues.first)
        #expect(identities.count == 2) // Only the 2 OTP items

        let otpIdentities = identities.compactMap { $0 as? ASOneTimeCodeCredentialIdentity }
        #expect(otpIdentities.count == 2)

        let identity1 = try #require(otpIdentities.first(where: { $0.label == "user1" }))
        #expect(identity1.serviceIdentifier.identifier == "example.com")
        #expect(identity1.recordIdentifier == item1.id.rawValue.uuidString)

        let identity2 = try #require(otpIdentities.first(where: { $0.label == "user2" }))
        #expect(identity2.serviceIdentifier.identifier == "test.com")
        #expect(identity2.recordIdentifier == item2.id.rawValue.uuidString)
    }

    @Test
    func syncAll_emptyItems_clearsStore() async throws {
        let spy = CredentialIdentityStoreMock()
        let sut = makeSUT(store: spy)

        try await sut.syncAll(items: [])

        #expect(spy.removeAllCredentialIdentitiesCallCount == 1)
        #expect(spy.saveCredentialIdentitiesCallCount == 0)
    }

    @Test
    func syncAll_onlyNonOTPItems_clearsStore() async throws {
        let spy = CredentialIdentityStoreMock()
        let sut = makeSUT(store: spy)

        let item1 = uniqueVaultItem(item: .secureNote(.init(title: "Note 1", contents: "Content", format: .plain)))
        let item2 = uniqueVaultItem(item: .secureNote(.init(title: "Note 2", contents: "Content", format: .plain)))

        try await sut.syncAll(items: [item1, item2])

        #expect(spy.removeAllCredentialIdentitiesCallCount == 1)
        #expect(spy.saveCredentialIdentitiesCallCount == 0)
    }

    @Test
    func sync_hiddenOTPItem_removesFromStore() async throws {
        let spy = CredentialIdentityStoreMock()
        let sut = makeSUT(store: spy)
        let id = UUID()
        let code = anyOTPAuthCode()

        try await sut.sync(
            id: id,
            item: anyItemWrite(.otpCode(code), visibility: .onlySearch, searchableLevel: .onlyPassphrase),
        )

        // Should remove from autofill store, not save
        #expect(spy.removeCredentialIdentitiesCallCount == 1)
        #expect(spy.saveCredentialIdentitiesCallCount == 0)

        let identities = try #require(spy.removeCredentialIdentitiesArgValues.first)
        let identity = try #require(identities.first as? ASOneTimeCodeCredentialIdentity)
        #expect(identity.recordIdentifier == id.uuidString)
    }

    @Test
    func syncAll_hidesItemsWithRequiresSearchPassphrase() async throws {
        let spy = CredentialIdentityStoreMock()
        let sut = makeSUT(store: spy)

        let item1 = uniqueVaultItem(
            item: .otpCode(anyOTPAuthCode(accountName: "user1", issuerName: "example.com")),
            visibility: .always,
            searchableLevel: .full,
        )
        let item2 = uniqueVaultItem(
            item: .otpCode(anyOTPAuthCode(accountName: "user2", issuerName: "test.com")),
            visibility: .onlySearch,
            searchableLevel: .onlyPassphrase,
        )
        let item3 = uniqueVaultItem(
            item: .otpCode(anyOTPAuthCode(accountName: "user3", issuerName: "demo.com")),
            visibility: .always,
            searchableLevel: .full,
        )

        try await sut.syncAll(items: [item1, item2, item3])

        #expect(spy.removeAllCredentialIdentitiesCallCount == 1)
        #expect(spy.saveCredentialIdentitiesCallCount == 1)

        let identities = try #require(spy.saveCredentialIdentitiesArgValues.first)
        #expect(identities.count == 2) // Only the 2 visible OTP items

        let otpIdentities = identities.compactMap { $0 as? ASOneTimeCodeCredentialIdentity }
        #expect(otpIdentities.count == 2)

        // Verify only the visible items are included
        let identity1 = try #require(otpIdentities.first(where: { $0.label == "user1" }))
        #expect(identity1.recordIdentifier == item1.id.rawValue.uuidString)

        let identity3 = try #require(otpIdentities.first(where: { $0.label == "user3" }))
        #expect(identity3.recordIdentifier == item3.id.rawValue.uuidString)

        // Verify the hidden item is not included
        #expect(otpIdentities.first(where: { $0.label == "user2" }) == nil)
    }

    /// A locked code isn't suggested in QuickType, which would show its site and account without unlocking it.
    @Test
    func sync_lockedOTPItem_removesFromStore() async throws {
        let spy = CredentialIdentityStoreMock()
        let sut = makeSUT(store: spy)
        let id = UUID()

        try await sut.sync(
            id: id,
            item: anyItemWrite(.otpCode(anyOTPAuthCode()), lockState: .lockedWithNativeSecurity),
        )

        #expect(spy.saveCredentialIdentitiesCallCount == 0)
        #expect(spy.removeCredentialIdentitiesCallCount == 1)
        let identities = try #require(spy.removeCredentialIdentitiesArgValues.first)
        let identity = try #require(identities.first as? ASOneTimeCodeCredentialIdentity)
        #expect(identity.recordIdentifier == id.uuidString)
    }

    @Test
    func syncAll_excludesLockedItems() async throws {
        let spy = CredentialIdentityStoreMock()
        let sut = makeSUT(store: spy)
        let unlocked = uniqueVaultItem(item: .otpCode(anyOTPAuthCode(accountName: "user1", issuerName: "example.com")))
        let locked = uniqueVaultItem(
            item: .otpCode(anyOTPAuthCode(accountName: "user2", issuerName: "test.com")),
            lockState: .lockedWithNativeSecurity,
        )

        try await sut.syncAll(items: [unlocked, locked])

        let identities = try #require(spy.saveCredentialIdentitiesArgValues.first)
        let otpIdentities = identities.compactMap { $0 as? ASOneTimeCodeCredentialIdentity }
        #expect(otpIdentities.map(\.recordIdentifier) == [unlocked.id.rawValue.uuidString])
    }

    @Test
    func syncAll_onlyLockedItems_clearsStore() async throws {
        let spy = CredentialIdentityStoreMock()
        let sut = makeSUT(store: spy)
        let locked = uniqueVaultItem(lockState: .lockedWithNativeSecurity)

        try await sut.syncAll(items: [locked])

        #expect(spy.removeAllCredentialIdentitiesCallCount == 1)
        #expect(spy.saveCredentialIdentitiesCallCount == 0)
    }

    @Test
    func sync_otpItemWithShowInQuickTypeFalse_removesFromStore() async throws {
        let spy = CredentialIdentityStoreMock()
        let sut = makeSUT(store: spy)
        let id = UUID()
        let code = anyOTPAuthCode()

        try await sut.sync(
            id: id,
            item: anyItemWrite(.otpCode(code), showInQuickType: false),
        )

        // Should remove from autofill store, not save
        #expect(spy.removeCredentialIdentitiesCallCount == 1)
        #expect(spy.saveCredentialIdentitiesCallCount == 0)

        let identities = try #require(spy.removeCredentialIdentitiesArgValues.first)
        let identity = try #require(identities.first as? ASOneTimeCodeCredentialIdentity)
        #expect(identity.recordIdentifier == id.uuidString)
    }

    @Test
    func syncAll_excludesItemsWithShowInQuickTypeFalse() async throws {
        let spy = CredentialIdentityStoreMock()
        let sut = makeSUT(store: spy)

        let item1 = uniqueVaultItem(
            item: .otpCode(anyOTPAuthCode(accountName: "user1", issuerName: "example.com")),
        )
        let item2 = anyOTPAuthCode(accountName: "user2", issuerName: "test.com")
            .wrapInAnyVaultItem(showInQuickType: false)
        let item3 = uniqueVaultItem(
            item: .otpCode(anyOTPAuthCode(accountName: "user3", issuerName: "demo.com")),
        )

        try await sut.syncAll(items: [item1, item2, item3])

        #expect(spy.removeAllCredentialIdentitiesCallCount == 1)
        #expect(spy.saveCredentialIdentitiesCallCount == 1)

        let identities = try #require(spy.saveCredentialIdentitiesArgValues.first)
        #expect(identities.count == 2) // Only the 2 items with showInQuickType: true

        let otpIdentities = identities.compactMap { $0 as? ASOneTimeCodeCredentialIdentity }
        #expect(otpIdentities.count == 2)

        // Verify only the visible items are included
        #expect(otpIdentities.first(where: { $0.label == "user1" }) != nil)
        #expect(otpIdentities.first(where: { $0.label == "user3" }) != nil)
        #expect(otpIdentities.first(where: { $0.label == "user2" }) == nil)
    }
}

// MARK: - Helpers

extension VaultOTPAutofillStoreImplTests {
    private func makeSUT(
        store: CredentialIdentityStoreMock = CredentialIdentityStoreMock(),
    ) -> VaultOTPAutofillStoreImpl {
        VaultOTPAutofillStoreImpl(store: store)
    }
}
