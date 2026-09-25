import Foundation
import TestHelpers
import Testing
import VaultKeygen
@testable import VaultFeed

struct BackupPasswordStoreImplTests {
    @Test
    func init_hasNoSecureStorageSideEffects() {
        let storage = SecureStorageMock()
        _ = makeSUT(secureStorage: storage)

        #expect(storage.retrieveCallCount == 0)
        #expect(storage.storeCallCount == 0)
        #expect(storage.attributesCallCount == 0)
    }

    @Test
    func fetchPassword_fetchErrorRethrowsError() async throws {
        let storage = SecureStorageMock()
        let sut = makeSUT(secureStorage: storage)
        storage.retrieveHandler = { _ in throw TestError() }

        await #expect(throws: (any Error).self) {
            try await sut.fetchPassword()
        }
    }

    @Test
    func fetchPassword_notFoundAnyReturnsNil() async throws {
        let storage = SecureStorageMock()
        let sut = makeSUT(secureStorage: storage)
        storage.retrieveHandler = { _ in nil }

        let password = try await sut.fetchPassword()

        #expect(password == nil)
    }

    @Test
    func setPassword_errorInServiceIsRethrown() async throws {
        let storage = SecureStorageMock()
        let sut = makeSUT(secureStorage: storage)
        storage.storeHandler = { _, _ in
            throw TestError()
        }

        let password = anyBackupPassword()
        await #expect(throws: (any Error).self) {
            try await sut.set(password: password)
        }
    }

    @Test
    func setPassword_setsDataEncodedCorrectly() async throws {
        let storage = SecureStorageMock()
        let sut = makeSUT(secureStorage: storage)
        let newPassword = DerivedEncryptionKey(
            key: .random(),
            salt: Data.random(count: 45),
            keyDervier: .backupFastV1,
        )

        try await sut.set(password: newPassword)

        #expect(
            storage.storeArgValues.map(\.1) ==
                ["vault.secure-storage.backup-password.v1"],
        )
    }

    @Test
    func fetchPasswordMetadata_readsAttributesNotData() async throws {
        let storage = SecureStorageMock()
        let sut = makeSUT(secureStorage: storage)
        storage.attributesHandler = { _ in .init(modificationDate: nil) }

        _ = try await sut.fetchPasswordMetadata()

        #expect(storage.attributesArgValues == ["vault.secure-storage.backup-password.v1"])
        #expect(storage.retrieveCallCount == 0)
    }

    @Test
    func fetchPasswordMetadata_lastSetDateIsModificationDate() async throws {
        let storage = SecureStorageMock()
        let sut = makeSUT(secureStorage: storage)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        storage.attributesHandler = { _ in .init(modificationDate: date) }

        let metadata = try await sut.fetchPasswordMetadata()

        #expect(metadata == BackupPasswordMetadata(lastSetDate: date))
    }

    @Test
    func fetchPasswordMetadata_notFoundReturnsNil() async throws {
        let storage = SecureStorageMock()
        let sut = makeSUT(secureStorage: storage)
        storage.attributesHandler = { _ in nil }

        let metadata = try await sut.fetchPasswordMetadata()

        #expect(metadata == nil)
    }

    @Test
    func fetchPasswordMetadata_fetchErrorRethrowsError() async throws {
        let storage = SecureStorageMock()
        let sut = makeSUT(secureStorage: storage)
        storage.attributesHandler = { _ in throw TestError() }

        await #expect(throws: (any Error).self) {
            try await sut.fetchPasswordMetadata()
        }
    }
}

// MARK: - Helpers

extension BackupPasswordStoreImplTests {
    private func makeSUT(
        secureStorage: SecureStorageMock = SecureStorageMock(),
    ) -> BackupPasswordStoreImpl {
        BackupPasswordStoreImpl(secureStorage: secureStorage)
    }

    private func anyBackupPassword() -> DerivedEncryptionKey {
        DerivedEncryptionKey(key: .zero(), salt: Data(), keyDervier: .testing)
    }
}
