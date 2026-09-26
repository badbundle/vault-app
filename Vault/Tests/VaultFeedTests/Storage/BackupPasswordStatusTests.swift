import Foundation
import TestHelpers
import Testing
import VaultCore
import VaultKeygen
@testable import VaultFeed

/// The backup password status as the Backups page and the Backup Password sheet see it, through the
/// real store, over secure storage where the password's own attributes can't be read without
/// authenticating (as on a device with a passcode).
@MainActor
struct BackupPasswordStatusTests {
    private let storage = InMemorySecureStorage(canReadAttributesWithoutAuthentication: false)
    private let setDate = Date(timeIntervalSince1970: 1_700_000_000)

    @Test
    func revisitingAfterSettingPassword_staysSet() async throws {
        let sut = makeSUT()
        try await sut.store(backupPassword: anyBackupPassword())

        await sut.loadBackupPasswordStatus()

        #expect(sut.backupPasswordStatus == .set(.init(lastSetDate: setDate)))
    }

    @Test
    func relaunchingAfterSettingPassword_isSetWithoutAuthenticating() async throws {
        try await makeSUT().store(backupPassword: anyBackupPassword())
        let retrievesBefore = await storage.authenticatedRetrieveCount

        let relaunched = makeSUT()
        await relaunched.loadBackupPasswordStatus()

        #expect(relaunched.backupPasswordStatus == .set(.init(lastSetDate: setDate)))
        #expect(await storage.authenticatedRetrieveCount == retrievesBefore)
    }

    @Test
    func lockingAndUnlocking_staysSet() async throws {
        let sut = makeSUT()
        try await sut.store(backupPassword: anyBackupPassword())

        sut.purgeSensitiveData()
        await sut.loadBackupPasswordStatus()

        #expect(sut.backupPasswordStatus == .set(.init(lastSetDate: setDate)))
    }

    @Test
    func changingPassword_updatesLastSetDate() async throws {
        let clock = EpochClockMock(currentTime: setDate.timeIntervalSince1970)
        let sut = makeSUT(clock: clock)
        try await sut.store(backupPassword: anyBackupPassword())

        clock.currentTime += 60
        try await sut.store(backupPassword: anyBackupPassword())
        await sut.loadBackupPasswordStatus()

        #expect(sut.backupPasswordStatus == .set(.init(lastSetDate: setDate.addingTimeInterval(60))))
    }

    @Test
    func noPassword_isNotSet() async {
        let sut = makeSUT()

        await sut.loadBackupPasswordStatus()

        #expect(sut.backupPasswordStatus == .notSet)
    }

    /// Passwords set before the status was recorded can't be seen without authenticating, until
    /// the password is next loaded.
    @Test
    func passwordSetBeforeStatusWasRecorded_isKnownOnceLoaded() async throws {
        try await makeSUT().store(backupPassword: anyBackupPassword())
        await storage.remove(key: VaultIdentifiers.SecureStorageKey.backupPasswordMetadata)
        let sut = makeSUT()

        await sut.loadBackupPasswordStatus()
        #expect(sut.backupPasswordStatus == .unknown)

        await sut.loadBackupPassword()
        #expect(sut.backupPasswordStatus == .set(.init(lastSetDate: nil)))

        let relaunched = makeSUT()
        await relaunched.loadBackupPasswordStatus()
        #expect(relaunched.backupPasswordStatus == .set(.init(lastSetDate: nil)))
    }

    /// Where the password's attributes are readable without authenticating, older passwords show
    /// straight away, with when they were set.
    @Test
    func passwordSetBeforeStatusWasRecorded_usesReadableAttributes() async throws {
        let storage = InMemorySecureStorage(canReadAttributesWithoutAuthentication: true, modificationDate: setDate)
        try await makeSUT(storage: storage).store(backupPassword: anyBackupPassword())
        await storage.remove(key: VaultIdentifiers.SecureStorageKey.backupPasswordMetadata)
        let sut = makeSUT(storage: storage)

        await sut.loadBackupPasswordStatus()

        #expect(sut.backupPasswordStatus == .set(.init(lastSetDate: setDate)))
    }

    /// If the record outlives the password (say, restored on its own from a device backup),
    /// loading the password puts it right.
    @Test
    func statusWithoutPassword_isClearedOnceLoaded() async throws {
        try await makeSUT().store(backupPassword: anyBackupPassword())
        await storage.remove(key: VaultIdentifiers.SecureStorageKey.backupPassword)
        let sut = makeSUT()
        await sut.loadBackupPasswordStatus()

        await sut.loadBackupPassword()
        #expect(sut.backupPassword == .notCreated)
        #expect(sut.backupPasswordStatus == .notSet)

        let relaunched = makeSUT()
        await relaunched.loadBackupPasswordStatus()
        #expect(relaunched.backupPasswordStatus == .notSet)
    }
}

// MARK: - Helpers

extension BackupPasswordStatusTests {
    private func makeSUT(
        storage: InMemorySecureStorage? = nil,
        clock: EpochClockMock? = nil,
    ) -> VaultDataModel {
        let store = BackupPasswordStoreImpl(
            secureStorage: storage ?? self.storage,
            clock: clock ?? EpochClockMock(currentTime: setDate.timeIntervalSince1970),
        )
        return anyVaultDataModel(backupPasswordStore: store)
    }

    private func anyBackupPassword() -> DerivedEncryptionKey {
        DerivedEncryptionKey(key: .random(), salt: Data(), keyDervier: .testing)
    }
}
