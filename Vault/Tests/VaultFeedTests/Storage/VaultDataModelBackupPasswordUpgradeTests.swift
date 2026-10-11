import Foundation
import FoundationExtensions
import TestHelpers
import Testing
import VaultKeygen
@testable import VaultFeed

/// Loading a backup password set before v2 moves its key on to v2 in the background (VAULT-128). These use the fast
/// derivations debug builds use, with the same shape as the secure ones.
@MainActor
struct VaultDataModelBackupPasswordUpgradeTests {
    @Test
    func loadBackupPassword_v1Key_storesItCarriedOnToV2AndBacksUpWithIt() async throws {
        let store = BackupPasswordStoreMock()
        let old = try fastV1Key()
        store.fetchPasswordHandler = { old }
        let sut = makeSUT(
            backupPasswordStore: store,
            upgrader: BackupPasswordUpgrader(keyDeriverFactory: VaultKeyDeriverFactoryImpl()),
        )

        await sut.loadBackupPassword()
        await sut.finishUpgradingBackupPassword()

        let upgraded = try VaultKeyDeriver.Backup.Fast.v1ThenV2.continueDerivation(from: old)
        #expect(store.upgradePasswordArgValues.map(\.0) == [old])
        #expect(store.upgradePasswordArgValues.map(\.1) == [upgraded])
        #expect(sut.backupPassword == .fetched(upgraded))
        // Not a new password, so it isn't set again.
        #expect(store.setCallCount == 0)
    }

    @Test
    func loadBackupPassword_withoutAnUpgrader_keepsTheKey() async throws {
        let store = BackupPasswordStoreMock()
        let old = try fastV1Key()
        store.fetchPasswordHandler = { old }
        let sut = makeSUT(backupPasswordStore: store, upgrader: nil)

        await sut.loadBackupPassword()
        await sut.finishUpgradingBackupPassword()

        #expect(store.upgradePasswordCallCount == 0)
        #expect(sut.backupPassword == .fetched(old))
    }

    @Test(arguments: [
        VaultKeyDeriver.Signature.backupFastV2,
        .backupSecureV2,
        .backupFastV1ThenV2,
        .backupSecureV1ThenV2,
        .testing,
    ])
    func loadBackupPassword_keyWithNothingStrongerForIt_isLeftAsItIs(signature: VaultKeyDeriver.Signature) async {
        let store = BackupPasswordStoreMock()
        let key = DerivedEncryptionKey(key: .random(), salt: .random(count: 48), keyDervier: signature)
        store.fetchPasswordHandler = { key }
        let upgrader = BackupPasswordUpgradingMock()
        let sut = makeSUT(backupPasswordStore: store, upgrader: upgrader)

        await sut.loadBackupPassword()
        await sut.finishUpgradingBackupPassword()

        #expect(upgrader.upgradedCallCount == 0)
        #expect(store.upgradePasswordCallCount == 0)
        #expect(sut.backupPassword == .fetched(key))
    }

    /// The upgrade takes seconds. Meanwhile auto-backup and the Backups page use the key that was loaded.
    @Test
    func loadBackupPassword_whileUpgrading_backupsUseTheOldKey() async throws {
        let store = BackupPasswordStoreMock()
        let old = try fastV1Key()
        store.fetchPasswordHandler = { old }
        let upgrader = SuspendedUpgrader()
        let sut = makeSUT(backupPasswordStore: store, upgrader: upgrader)

        await sut.loadBackupPassword()
        try await upgrader.started.wait()

        #expect(sut.backupPassword == .fetched(old))
        #expect(store.upgradePasswordCallCount == 0)

        await upgrader.release.fulfill()
        await sut.finishUpgradingBackupPassword()
        #expect(sut.backupPassword == .fetched(upgrader.upgradedKey))
    }

    @Test
    func storeBackupPassword_whileUpgrading_keepsTheNewPassword() async throws {
        let store = BackupPasswordStoreMock()
        let old = try fastV1Key()
        store.fetchPasswordHandler = { old }
        store.fetchPasswordMetadataHandler = { nil }
        let upgrader = SuspendedUpgrader()
        let sut = makeSUT(backupPasswordStore: store, upgrader: upgrader)
        await sut.loadBackupPassword()
        try await upgrader.started.wait()

        let new = try VaultKeyDeriver.Backup.Fast.v2.createEncryptionKey(password: "a new password")
        try await sut.store(backupPassword: new)
        await upgrader.release.fulfill()
        await sut.finishUpgradingBackupPassword()

        #expect(store.upgradePasswordCallCount == 0)
        #expect(sut.backupPassword == .fetched(new))
    }

    @Test
    func deleteVault_whileUpgrading_storesNoPassword() async throws {
        let store = BackupPasswordStoreMock()
        let old = try fastV1Key()
        store.fetchPasswordHandler = { old }
        let upgrader = SuspendedUpgrader()
        let sut = makeSUT(backupPasswordStore: store, upgrader: upgrader)
        await sut.loadBackupPassword()
        try await upgrader.started.wait()

        try await sut.deleteVault()
        await upgrader.release.fulfill()
        await sut.finishUpgradingBackupPassword()

        #expect(store.upgradePasswordCallCount == 0)
        #expect(sut.backupPassword == .notCreated)
    }

    @Test
    func openVaultDidChange_whileUpgrading_storesNothing() async throws {
        let store = BackupPasswordStoreMock()
        let old = try fastV1Key()
        store.fetchPasswordHandler = { old }
        store.fetchPasswordMetadataHandler = { nil }
        let upgrader = SuspendedUpgrader()
        let sut = makeSUT(backupPasswordStore: store, upgrader: upgrader)
        await sut.loadBackupPassword()
        try await upgrader.started.wait()

        await sut.openVaultDidChange()
        await upgrader.release.fulfill()
        await sut.finishUpgradingBackupPassword()

        #expect(store.upgradePasswordCallCount == 0)
        #expect(sut.backupPassword == .notFetched)
    }

    /// The app going to the background forgets the key, but it's still the same password, so the upgrade is kept.
    @Test
    func purgeSensitiveData_whileUpgrading_stillStoresTheUpgradeButHoldsNoKey() async throws {
        let store = BackupPasswordStoreMock()
        let old = try fastV1Key()
        store.fetchPasswordHandler = { old }
        let upgrader = SuspendedUpgrader()
        let sut = makeSUT(backupPasswordStore: store, upgrader: upgrader)
        await sut.loadBackupPassword()
        try await upgrader.started.wait()

        sut.purgeSensitiveData()
        await upgrader.release.fulfill()
        await sut.finishUpgradingBackupPassword()

        #expect(store.upgradePasswordArgValues.map(\.1) == [upgrader.upgradedKey])
        #expect(sut.backupPassword == .notFetched)
    }

    @Test
    func upgrade_failingToDerive_leavesTheKeyAndTriesAgainNextLoad() async throws {
        let store = BackupPasswordStoreMock()
        let old = try fastV1Key()
        store.fetchPasswordHandler = { old }
        let upgrader = BackupPasswordUpgradingMock()
        upgrader.upgradedHandler = { _ in throw TestError() }
        let sut = makeSUT(backupPasswordStore: store, upgrader: upgrader)

        await sut.loadBackupPassword()
        await sut.finishUpgradingBackupPassword()

        #expect(store.upgradePasswordCallCount == 0)
        #expect(sut.backupPassword == .fetched(old))

        sut.purgeSensitiveData()
        await sut.loadBackupPassword()
        await sut.finishUpgradingBackupPassword()
        #expect(upgrader.upgradedCallCount == 2)
    }

    @Test
    func upgrade_failingToStore_leavesTheKey() async throws {
        let store = BackupPasswordStoreMock()
        let old = try fastV1Key()
        store.fetchPasswordHandler = { old }
        store.upgradePasswordHandler = { _, _ in throw TestError() }
        let sut = makeSUT(
            backupPasswordStore: store,
            upgrader: BackupPasswordUpgrader(keyDeriverFactory: VaultKeyDeriverFactoryImpl()),
        )

        await sut.loadBackupPassword()
        await sut.finishUpgradingBackupPassword()

        #expect(store.upgradePasswordCallCount == 1)
        #expect(sut.backupPassword == .fetched(old))
        #expect(!sut.backupPassword.isError)
    }

    /// End to end with an encrypted vault's settings: the stored key is replaced, and when the password was set isn't.
    @Test
    func loadBackupPassword_encryptedVault_replacesTheKeyAndKeepsWhenItWasSet() async throws {
        let old = try fastV1Key()
        let setDate = Date(timeIntervalSince1970: 1_700_000_000)
        let fixture = try EncryptedVaultFixture(state: .empty(with: VaultBackupSettings(
            backupPassword: StoredBackupPassword(password: old, lastSetDate: setDate),
        )))
        let session = try await VaultStoreSession(target: .unlocked(fixture.openStore()))
        let settings = try OpenVaultBackupSettings.inMemory(session: session)
        await settings.reload()
        let sut = makeSUT(
            backupPasswordStore: settings,
            upgrader: BackupPasswordUpgrader(keyDeriverFactory: VaultKeyDeriverFactoryImpl()),
        )

        await sut.loadBackupPassword()
        await sut.finishUpgradingBackupPassword()

        let upgraded = try VaultKeyDeriver.Backup.Fast.v1ThenV2.continueDerivation(from: old)
        #expect(try fixture.savedState().vault.settings.backupPassword == StoredBackupPassword(
            password: upgraded,
            lastSetDate: setDate,
        ))
        #expect(sut.backupPassword == .fetched(upgraded))
    }
}

// MARK: - Helpers

extension VaultDataModelBackupPasswordUpgradeTests {
    private func makeSUT(
        backupPasswordStore: any BackupPasswordStore,
        upgrader: (any BackupPasswordUpgrading)?,
    ) -> VaultDataModel {
        VaultDataModel(
            vaultStore: VaultStoreStub(),
            vaultTagStore: VaultTagStoreStub(),
            vaultImporter: VaultStoreImporterMock(),
            vaultDeleter: VaultStoreDeleterMock(),
            vaultKillphraseDeleter: VaultStoreKillphraseDeleterMock(),
            vaultOtpAutofillStore: VaultOTPAutofillStoreMock(),
            backupPasswordStore: backupPasswordStore,
            killphraseKeyStore: StubKillphraseKeyStore(),
            killphraseRehashService: nil,
            searchPassphraseKeyStore: StubSearchPassphraseKeyStore(),
            searchPassphraseRehashService: nil,
            backupEventLogger: BackupEventLoggerMock(),
            backupPasswordUpgrader: upgrader,
        )
    }

    /// A backup password's key as a debug build set it before v2.
    private func fastV1Key() throws -> DerivedEncryptionKey {
        try VaultKeyDeriver.Backup.Fast.v1.createEncryptionKey(password: "correct horse battery staple")
    }
}

/// Holds the upgrade until it's released.
private final class SuspendedUpgrader: BackupPasswordUpgrading {
    let started = Pending<Void>.signal()
    let release = Pending<Void>.signal()
    let upgradedKey = DerivedEncryptionKey(key: .random(), salt: .random(count: 48), keyDervier: .backupFastV1ThenV2)

    func upgraded(_: DerivedEncryptionKey) async throws -> DerivedEncryptionKey? {
        await started.fulfill()
        try await release.wait()
        return upgradedKey
    }
}
