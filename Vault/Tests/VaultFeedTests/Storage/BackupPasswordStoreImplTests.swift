import Foundation
import TestHelpers
import Testing
import VaultCore
import VaultKeygen
@testable import VaultFeed

struct BackupPasswordStoreImplTests {
    @Test
    func init_hasNoSecureStorageSideEffects() {
        let storage = SecureStorageMock()
        _ = makeSUT(secureStorage: storage)

        #expect(storage.retrieveCallCount == 0)
        #expect(storage.storeCallCount == 0)
        #expect(storage.retrieveSilentCallCount == 0)
        #expect(storage.storeSilentCallCount == 0)
        #expect(storage.attributesCallCount == 0)
        #expect(storage.removeCallCount == 0)
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
    func fetchPassword_returnsStoredPassword() async throws {
        let storage = InMemorySecureStorage()
        let sut = makeSUT(secureStorage: storage)
        let password = anyBackupPassword()
        try await sut.set(password: password)

        let fetched = try await sut.fetchPassword()

        #expect(fetched == password)
    }

    @Test
    func fetchPassword_notFoundRemovesMetadata() async throws {
        let storage = SecureStorageMock()
        let sut = makeSUT(secureStorage: storage)
        storage.retrieveHandler = { _ in nil }

        _ = try await sut.fetchPassword()

        #expect(storage.removeArgValues == [metadataKey])
    }

    @Test
    func fetchPassword_notFoundIgnoresErrorRemovingMetadata() async throws {
        let storage = SecureStorageMock()
        let sut = makeSUT(secureStorage: storage)
        storage.retrieveHandler = { _ in nil }
        storage.removeHandler = { _ in throw TestError() }

        let password = try await sut.fetchPassword()

        #expect(password == nil)
    }

    /// Passwords set before the store kept metadata get it once they've been loaded.
    @Test
    func fetchPassword_recordsMissingMetadataWithModificationDate() async throws {
        let date = Date(timeIntervalSince1970: 1_600_000_000)
        let storage = InMemorySecureStorage(canReadAttributesWithoutAuthentication: true, modificationDate: date)
        let sut = makeSUT(secureStorage: storage)
        try await sut.set(password: anyBackupPassword())
        await storage.remove(key: metadataKey)

        _ = try await sut.fetchPassword()

        #expect(await storage.contains(key: metadataKey))
        #expect(try await sut.fetchPasswordMetadata() == BackupPasswordMetadata(lastSetDate: date))
    }

    @Test
    func fetchPassword_recordsMissingMetadataWithoutDateIfAttributesUnreadable() async throws {
        let storage = InMemorySecureStorage(canReadAttributesWithoutAuthentication: false)
        let sut = makeSUT(secureStorage: storage)
        try await sut.set(password: anyBackupPassword())
        await storage.remove(key: metadataKey)

        _ = try await sut.fetchPassword()

        #expect(try await sut.fetchPasswordMetadata() == BackupPasswordMetadata(lastSetDate: nil))
    }

    @Test
    func fetchPassword_keepsExistingMetadata() async throws {
        let storage = InMemorySecureStorage(canReadAttributesWithoutAuthentication: true)
        let sut = makeSUT(secureStorage: storage, clock: EpochClockMock(currentTime: 1_700_000_000))
        try await sut.set(password: anyBackupPassword())

        _ = try await sut.fetchPassword()

        let metadata = try await sut.fetchPasswordMetadata()
        #expect(metadata == BackupPasswordMetadata(lastSetDate: Date(timeIntervalSince1970: 1_700_000_000)))
    }

    @Test
    func fetchPassword_errorRecordingMetadataStillReturnsPassword() async throws {
        let storage = SecureStorageMock()
        let sut = makeSUT(secureStorage: storage)
        let password = anyBackupPassword()
        try await sut.set(password: password)
        let storedPassword = try #require(storage.storeArgValues.first?.data)
        storage.retrieveHandler = { _ in storedPassword }
        storage.retrieveSilentHandler = { _ in nil }
        storage.storeSilentHandler = { _, _ in throw TestError() }

        let fetched = try await sut.fetchPassword()

        #expect(fetched == password)
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
    func setPassword_errorInServiceDoesNotRecordMetadata() async throws {
        let storage = SecureStorageMock()
        let sut = makeSUT(secureStorage: storage)
        storage.storeHandler = { _, _ in
            throw TestError()
        }

        _ = try? await sut.set(password: anyBackupPassword())

        #expect(storage.storeSilentCallCount == 0)
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

    /// The metadata has to be readable without authenticating, so it's stored silently, apart
    /// from the password.
    @Test
    func setPassword_recordsMetadataSilently() async throws {
        let storage = SecureStorageMock()
        let sut = makeSUT(secureStorage: storage)

        try await sut.set(password: anyBackupPassword())

        #expect(storage.storeSilentArgValues.map(\.1) == ["vault.secure-storage.backup-password-metadata.v1"])
    }

    @Test
    func setPassword_metadataLastSetDateIsCurrentDate() async throws {
        let storage = InMemorySecureStorage()
        let sut = makeSUT(secureStorage: storage, clock: EpochClockMock(currentTime: 1_700_000_000))

        try await sut.set(password: anyBackupPassword())

        let metadata = try await sut.fetchPasswordMetadata()
        #expect(metadata == BackupPasswordMetadata(lastSetDate: Date(timeIntervalSince1970: 1_700_000_000)))
    }

    /// The password is stored by then, so failing to record it mustn't look like the change failed.
    @Test
    func setPassword_errorRecordingMetadataIsIgnored() async throws {
        let storage = SecureStorageMock()
        let sut = makeSUT(secureStorage: storage)
        storage.storeSilentHandler = { _, _ in throw TestError() }

        try await sut.set(password: anyBackupPassword())

        #expect(storage.storeCallCount == 1)
    }

    @Test
    func fetchPasswordMetadata_readsRecordNotPassword() async throws {
        let storage = InMemorySecureStorage(canReadAttributesWithoutAuthentication: false)
        let sut = makeSUT(secureStorage: storage)
        try await sut.set(password: anyBackupPassword())

        let metadata = try await sut.fetchPasswordMetadata()

        #expect(metadata != nil)
        #expect(await storage.authenticatedRetrieveCount == 0)
    }

    @Test
    func fetchPasswordMetadata_undecodableRecordStillMeansSet() async throws {
        let storage = SecureStorageMock()
        let sut = makeSUT(secureStorage: storage)
        storage.retrieveSilentHandler = { _ in Data("not metadata".utf8) }

        let metadata = try await sut.fetchPasswordMetadata()

        #expect(metadata == BackupPasswordMetadata(lastSetDate: nil))
        #expect(storage.attributesCallCount == 0)
    }

    @Test
    func fetchPasswordMetadata_recordErrorRethrowsError() async throws {
        let storage = SecureStorageMock()
        let sut = makeSUT(secureStorage: storage)
        storage.retrieveSilentHandler = { _ in throw TestError() }

        await #expect(throws: (any Error).self) {
            try await sut.fetchPasswordMetadata()
        }
    }

    @Test
    func fetchPasswordMetadata_withoutRecordReadsAttributesNotData() async throws {
        let storage = SecureStorageMock()
        let sut = makeSUT(secureStorage: storage)
        storage.retrieveSilentHandler = { _ in nil }
        storage.attributesHandler = { _ in .init(modificationDate: nil) }

        _ = try await sut.fetchPasswordMetadata()

        #expect(storage.retrieveSilentArgValues == ["vault.secure-storage.backup-password-metadata.v1"])
        #expect(storage.attributesArgValues == ["vault.secure-storage.backup-password.v1"])
        #expect(storage.retrieveCallCount == 0)
    }

    @Test
    func fetchPasswordMetadata_withoutRecordLastSetDateIsModificationDate() async throws {
        let storage = SecureStorageMock()
        let sut = makeSUT(secureStorage: storage)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        storage.retrieveSilentHandler = { _ in nil }
        storage.attributesHandler = { _ in .init(modificationDate: date) }

        let metadata = try await sut.fetchPasswordMetadata()

        #expect(metadata == BackupPasswordMetadata(lastSetDate: date))
    }

    @Test
    func fetchPasswordMetadata_notFoundReturnsNil() async throws {
        let storage = SecureStorageMock()
        let sut = makeSUT(secureStorage: storage)
        storage.retrieveSilentHandler = { _ in nil }
        storage.attributesHandler = { _ in nil }

        let metadata = try await sut.fetchPasswordMetadata()

        #expect(metadata == nil)
    }

    @Test
    func fetchPasswordMetadata_withoutRecordAttributesErrorRethrowsError() async throws {
        let storage = SecureStorageMock()
        let sut = makeSUT(secureStorage: storage)
        storage.retrieveSilentHandler = { _ in nil }
        storage.attributesHandler = { _ in throw TestError() }

        await #expect(throws: (any Error).self) {
            try await sut.fetchPasswordMetadata()
        }
    }
}

// MARK: - Helpers

extension BackupPasswordStoreImplTests {
    private var metadataKey: String {
        VaultIdentifiers.SecureStorageKey.backupPasswordMetadata
    }

    private func makeSUT(
        secureStorage: any SecureStorage = SecureStorageMock(),
        clock: any EpochClock = EpochClockMock(currentTime: 100),
    ) -> BackupPasswordStoreImpl {
        BackupPasswordStoreImpl(secureStorage: secureStorage, clock: clock)
    }

    private func anyBackupPassword() -> DerivedEncryptionKey {
        DerivedEncryptionKey(key: .zero(), salt: Data(), keyDervier: .testing)
    }
}
