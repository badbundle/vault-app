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
    func removePassword_removesThePasswordAndItsRecord() async throws {
        let storage = InMemorySecureStorage()
        let sut = makeSUT(secureStorage: storage)
        try await sut.set(password: anyBackupPassword())

        try await sut.removePassword()

        #expect(try await sut.fetchPasswordMetadata() == nil)
        #expect(try await sut.fetchPassword() == nil)
    }

    /// An upgraded key's copy first, so it can't come back as the password, then the password: it's what decrypts
    /// backups. Removing never reads it, so never asks the user.
    @Test
    func removePassword_removesThePasswordBeforeItsRecordWithoutReadingIt() async throws {
        let storage = SecureStorageMock()
        let sut = makeSUT(secureStorage: storage)

        try await sut.removePassword()

        #expect(storage.removeArgValues == [upgradeKey, passwordKey, metadataKey])
        #expect(storage.retrieveCallCount == 0)
    }

    @Test
    func removePassword_errorRemovingThePasswordRethrowsAndKeepsTheRecord() async {
        let storage = SecureStorageMock()
        let sut = makeSUT(secureStorage: storage)
        let passwordKey = passwordKey
        storage.removeHandler = { key in
            if key == passwordKey {
                throw TestError()
            }
        }

        await #expect(throws: TestError.self) {
            try await sut.removePassword()
        }
        #expect(storage.removeArgValues == [upgradeKey, passwordKey])
    }

    @Test
    func removePassword_errorRemovingAnUpgradedKeyRethrowsAndKeepsThePassword() async throws {
        let storage = SecureStorageMock()
        let sut = makeSUT(secureStorage: storage)
        storage.removeHandler = { _ in throw TestError() }

        await #expect(throws: TestError.self) {
            try await sut.removePassword()
        }
        #expect(storage.removeArgValues == [upgradeKey])
    }

    // MARK: - Upgrade

    @Test
    func upgradePassword_replacesTheKeyAndKeepsWhenItWasSet() async throws {
        let storage = InMemorySecureStorage()
        let sut = makeSUT(secureStorage: storage, clock: EpochClockMock(currentTime: 1_700_000_000))
        let old = anyBackupPassword()
        try await sut.set(password: old)
        let new = upgradedPassword(of: old)

        try await sut.upgradePassword(from: old, to: new)

        #expect(try await sut.fetchPassword() == new)
        #expect(try await sut.fetchPasswordMetadata() == BackupPasswordMetadata(
            lastSetDate: Date(timeIntervalSince1970: 1_700_000_000),
        ))
        #expect(await !storage.contains(key: upgradeKey))
    }

    /// Reading the old key would ask the user to authenticate, in the middle of using the app.
    @Test
    func upgradePassword_neverReadsThePassword() async throws {
        let storage = InMemorySecureStorage()
        let sut = makeSUT(secureStorage: storage)
        let old = anyBackupPassword()
        try await sut.set(password: old)

        try await sut.upgradePassword(from: old, to: upgradedPassword(of: old))

        #expect(await storage.authenticatedRetrieveCount == 0)
    }

    @Test
    func upgradePassword_failingToKeepTheNewKey_changesNothing() async throws {
        let storage = SecureStorageMock()
        let sut = makeSUT(secureStorage: storage)
        let upgradeKey = upgradeKey
        storage.storeHandler = { _, key in
            if key == upgradeKey {
                throw TestError()
            }
        }

        await #expect(throws: TestError.self) {
            try await sut.upgradePassword(from: anyBackupPassword(), to: upgradedPassword(of: anyBackupPassword()))
        }
        #expect(storage.storeArgValues.map(\.1) == [upgradeKey])
        #expect(storage.removeCallCount == 0)
    }

    /// Replacing an item removes it, then adds the new one, and the add can fail, as it does while the device is
    /// locked. Then the password's gone, but the next load puts the new key back.
    @Test
    func upgradePassword_stoppingWithThePasswordRemoved_nextLoadRestoresTheNewKey() async throws {
        let storage = FailingAddSecureStorage(failingKey: passwordKey)
        let sut = makeSUT(secureStorage: storage)
        let old = anyBackupPassword()
        try await storage.underlying.store(data: encoded(old), forKey: passwordKey)
        let new = upgradedPassword(of: old)

        await #expect(throws: TestError.self) {
            try await sut.upgradePassword(from: old, to: new)
        }
        #expect(await !storage.underlying.contains(key: passwordKey))

        await storage.stopFailing()
        #expect(try await sut.fetchPassword() == new)
        #expect(await storage.underlying.contains(key: passwordKey))
        #expect(await !storage.underlying.contains(key: upgradeKey))
    }

    /// A new password removes the copy an interrupted upgrade left, so the copy can't come back in its place.
    @Test
    func setPassword_removesAnUpgradedKeyLeftBehindFirst() async throws {
        let storage = InMemorySecureStorage()
        let sut = makeSUT(secureStorage: storage)
        let old = anyBackupPassword()
        try await storage.store(data: encoded(upgradedPassword(of: old)), forKey: upgradeKey)
        let other = DerivedEncryptionKey(key: .random(), salt: .random(count: 48), keyDervier: .backupFastV2)

        try await sut.set(password: other)
        await storage.remove(key: passwordKey)

        #expect(try await sut.fetchPassword() == nil)
    }

    @Test
    func removePassword_removesAnUpgradedKeyLeftBehind() async throws {
        let storage = InMemorySecureStorage()
        let sut = makeSUT(secureStorage: storage)
        try await storage.store(data: encoded(upgradedPassword(of: anyBackupPassword())), forKey: upgradeKey)

        try await sut.removePassword()

        #expect(try await sut.fetchPassword() == nil)
        #expect(await !storage.contains(key: upgradeKey))
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
    private var passwordKey: String {
        VaultIdentifiers.SecureStorageKey.backupPassword.rawValue
    }

    private var metadataKey: String {
        VaultIdentifiers.SecureStorageKey.backupPasswordMetadata.rawValue
    }

    private var upgradeKey: String {
        VaultIdentifiers.SecureStorageKey.backupPasswordUpgrade.rawValue
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

    private func upgradedPassword(of password: DerivedEncryptionKey) -> DerivedEncryptionKey {
        DerivedEncryptionKey(key: .random(), salt: password.salt, keyDervier: .backupFastV1ThenV2)
    }

    /// The password as the store keeps it in the keychain.
    private func encoded(_ password: DerivedEncryptionKey) async throws -> Data {
        let storage = InMemorySecureStorage()
        try await makeSUT(secureStorage: storage).set(password: password)
        return try #require(await storage.retrieve(key: passwordKey))
    }
}

/// Keeps items in memory, but fails to add the item with `failingKey` until told to stop, after removing whatever was
/// there, as `SecureStorageImpl` does when the keychain won't add it.
private actor FailingAddSecureStorage: SecureStorage {
    let underlying = InMemorySecureStorage()
    private let failingKey: String
    private var isFailing = true

    init(failingKey: String) {
        self.failingKey = failingKey
    }

    func stopFailing() {
        isFailing = false
    }

    func store(data: Data, forKey key: String) async throws {
        if isFailing, key == failingKey {
            await underlying.remove(key: key)
            throw TestError()
        }
        await underlying.store(data: data, forKey: key)
    }

    func retrieve(key: String) async -> Data? {
        await underlying.retrieve(key: key)
    }

    func storeSilent(data: Data, forKey key: String) async {
        await underlying.storeSilent(data: data, forKey: key)
    }

    func retrieveSilent(key: String) async -> Data? {
        await underlying.retrieveSilent(key: key)
    }

    func attributes(key: String) async throws -> SecureStorageAttributes? {
        try await underlying.attributes(key: key)
    }

    func remove(key: String) async {
        await underlying.remove(key: key)
    }
}
