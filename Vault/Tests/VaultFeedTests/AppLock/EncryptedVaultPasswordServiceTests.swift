import CryptoKit
import Foundation
import FoundationExtensions
import TestHelpers
import Testing
@testable import VaultFeed

/// The App Lock Password end to end, as the app has it: `AppLockService` over `EncryptedVaultPasswordService`, over the
/// real conversion, unlock and change services, on a directory on disk. Only the key derivation's parameters are cheap,
/// the clocks are the test's, and the keychain is in memory.
@MainActor
struct EncryptedVaultPasswordServiceTests {
    private static let password = "correct horse"
    private static let duressPassword = "plausible decoy"
    private static let newPassword = "battery staple"

    /// Set a password, lock, unlock with a wrong, the right and a duress password, change it, turn it off and unlock
    /// with device authentication alone, then turn it back on.
    @Test
    func thePasswordFromSettingItToTurningItOffAndBackOn() async throws {
        try await withTemporaryDirectory { directory in
            let sut = try await SUT(directory: directory)
            let item = try await sut.insertItem()

            // Set it: the plain store becomes an encrypted vault, and the lock asks for the password from now on.
            #expect(try await sut.appLock.setPassword(Self.password))
            #expect(sut.service.mode == .password)
            #expect(sut.appLock.isPasswordSet)
            #expect(sut.appLock.isEnabled)
            #expect(try await sut.itemIDs() == [item])

            // Lock, then unlock with a wrong password and the right one.
            try await sut.lock()
            #expect(await sut.session.isLocked)
            await sut.appLock.unlock()
            #expect(sut.appLock.state == .locked(.init(step: .password)))
            await sut.appLock.unlock(password: "wrong password")
            #expect(sut.appLock.isLocked)
            await sut.appLock.unlock(password: Self.password)
            #expect(sut.appLock.state == .unlocked)
            #expect(try await sut.itemIDs() == [item])

            // Make a duress vault, which its password opens, empty.
            #expect(try await sut.appLock.makeDuressVault(password: Self.duressPassword))
            try await sut.unlockAgain(with: Self.duressPassword)
            #expect(try await sut.itemIDs().isEmpty)

            // Change the real vault's password: the old one no longer opens it.
            try await sut.unlockAgain(with: Self.password)
            #expect(try await sut.appLock.changePassword(current: Self.password, new: Self.newPassword) == .accepted)
            try await sut.lock()
            await sut.appLock.unlock()
            await sut.appLock.unlock(password: Self.password)
            #expect(sut.appLock.isLocked)
            await sut.appLock.unlock(password: Self.newPassword)
            #expect(sut.appLock.state == .unlocked)
            #expect(try await sut.itemIDs() == [item])

            // Turn it off: device authentication alone opens the vault, encrypted with the device key.
            #expect(try await sut.appLock.turnOffPassword(current: Self.newPassword) == .accepted)
            #expect(sut.service.mode == .deviceKey)
            #expect(!sut.appLock.isPasswordSet)
            try await sut.lock()
            #expect(await sut.session.isLocked)
            await sut.appLock.unlock()
            #expect(sut.appLock.state == .unlocked)
            #expect(try await sut.itemIDs() == [item])

            // Turn it back on, with another password.
            #expect(try await sut.appLock.setPassword(Self.password))
            #expect(sut.service.mode == .password)
            #expect(sut.appLock.isPasswordSet)
            try await sut.unlockAgain(with: Self.password)
            #expect(try await sut.itemIDs() == [item])
        }
    }

    /// With erasing after failed passwords on, the tenth wrong password in a row at the lock screen erases every vault,
    /// the duress one included, and the app opens a fresh, empty plain vault with no password, like a new install.
    @Test
    func unlock_tenthWrongPasswordWithErasingOn_erasesEveryVault() async throws {
        try await withTemporaryDirectory { directory in
            let sut = try await SUT(directory: directory)
            _ = try await sut.insertItem()
            #expect(try await sut.appLock.setPassword(Self.password))
            #expect(try await sut.appLock.makeDuressVault(password: Self.duressPassword))
            #expect(!sut.appLock.erasesAfterFailedPasswords)
            #expect(try await sut.appLock.setErasesAfterFailedPasswords(true, current: Self.password) == .accepted)
            #expect(sut.appLock.erasesAfterFailedPasswords)
            try await sut.lock()
            await sut.appLock.unlock()

            for attempt in 1 ... AppLockPasswordAttemptCounter.eraseThreshold {
                // Past any wait, so every attempt is tried.
                sut.keychain.attemptClock.advance(by: .seconds(24 * 60 * 60))
                await sut.appLock.unlock(password: "wrong password \(attempt)")
            }

            #expect(sut.appLock.state == .unlocked)
            #expect(!sut.appLock.isPasswordSet)
            #expect(!sut.appLock.erasesAfterFailedPasswords)
            #expect(sut.service.mode == .plain)
            #expect(try await sut.itemIDs().isEmpty)
            #expect(!FileManager.default.fileExists(
                atPath: directory.appending(path: EncryptedVaultFile.fileName).path(percentEncoded: false),
            ))
            #expect(sut.keychain.deviceKeys.key == nil)
            #expect(try sut.attemptStorage.load() == nil)

            // The fresh plain store is the one a new password encrypts.
            let item = try await sut.insertItem()
            #expect(try await sut.appLock.setPassword(Self.newPassword))
            try await sut.unlockAgain(with: Self.newPassword)
            #expect(try await sut.itemIDs() == [item])
        }
    }

    /// The app locks while the vault is converted: the lock finds the plain store, which it doesn't lock, and the
    /// conversion then opens the encrypted vault. It's locked again once the password is set, so nothing decrypted is
    /// open behind the lock screen, and the password opens it.
    @Test
    func setPassword_whileTheAppLocks_leavesTheVaultLockedUntilThePasswordOpensIt() async throws {
        try await withTemporaryDirectory { directory in
            let sut = try await SUT(directory: directory, isLockEnabled: true)
            await sut.appLock.unlock()
            let item = try await sut.insertItem()
            let appLock = sut.appLock
            sut.plainStore.whileReleasing = {
                appLock.scenePhaseDidChange(to: .background)
            }

            #expect(try await sut.appLock.setPassword(Self.password))
            await sut.appLock.vaultLock?.value

            #expect(sut.appLock.isLocked)
            #expect(await sut.session.isLocked)
            await sut.appLock.unlock()
            await sut.appLock.unlock(password: Self.password)
            #expect(sut.appLock.state == .unlocked)
            #expect(try await sut.itemIDs() == [item])
        }
    }

    /// The app locks while the password is tried, at its deadline. The attempt is thrown away, and the vault is
    /// locked, however the two land.
    @Test
    func lock_whileThePasswordIsTried_leavesTheVaultLocked() async throws {
        try await withTemporaryDirectory { directory in
            let sut = try await SUT(directory: directory)
            #expect(try await sut.appLock.setPassword(Self.password))
            try await sut.lock()
            await sut.appLock.unlock()
            sut.unlockClock.hold()
            let appLock = sut.appLock
            let attempt = Task { await appLock.unlock(password: Self.password) }
            await sut.unlockClock.waitUntilHolding()

            sut.appLock.scenePhaseDidChange(to: .background)
            sut.unlockClock.release()
            await attempt.value
            await sut.appLock.vaultLock?.value

            #expect(sut.appLock.isLocked)
            #expect(await sut.session.isLocked)
        }
    }

    /// The password was turned off, but this launch was told it's on: the lock asks for it after device
    /// authentication. It's refused before it's counted, and the vault opens with the device key, as device
    /// authentication has passed. The lock stops asking for the password.
    @Test
    func unlock_passwordOffButTakenToBeOn_opensWithTheDeviceKeyWithoutCounting() async throws {
        try await withTemporaryDirectory { directory in
            let keychain = try Keychain()
            let before = try await SUT(directory: directory, keychain: keychain)
            #expect(try await before.appLock.setPassword(Self.password))
            #expect(try await before.appLock.turnOffPassword(current: Self.password) == .accepted)
            try await before.lock()

            let sut = try await SUT(directory: directory, keychain: keychain, mode: .password)
            await sut.appLock.unlock()
            await sut.appLock.unlock(password: "anything")

            #expect(sut.appLock.state == .unlocked)
            #expect(!sut.appLock.isPasswordSet)
            #expect(sut.service.mode == .deviceKey)
            #expect(try keychain.attempts.load() == nil)
        }
    }

    /// Setting a new password starts with erasing off, whatever was left from before.
    @Test
    func setPassword_turnsErasingOff() async throws {
        try await withTemporaryDirectory { directory in
            let sut = try await SUT(directory: directory)
            sut.keychain.settings.erasesAfterFailedPasswords = true

            #expect(try await sut.appLock.setPassword(Self.password))

            #expect(!sut.keychain.settings.erasesAfterFailedPasswords)
            #expect(!sut.appLock.erasesAfterFailedPasswords)
        }
    }

    /// Copies of the vault set aside are deleted when the password is set, and only once the user agrees.
    @Test
    func setPassword_withSetAsideVaults_needsTheUsersAgreement() async throws {
        try await withTemporaryDirectory { directory in
            let archive = try VaultEncryptionConverterTests.makeArchive(in: directory)
            let sut = try await SUT(directory: directory)
            #expect(sut.appLock.setAsideVaultCount == 1)

            await #expect(throws: VaultEncryptionError.archivesNeedDeleting) {
                try await sut.appLock.setPassword(Self.password)
            }
            #expect(sut.service.mode == .plain)

            #expect(try await sut.appLock.setPassword(Self.password, deletingSetAsideVaults: true))
            #expect(sut.service.mode == .password)
            #expect(!FileManager.default.fileExists(atPath: archive.path(percentEncoded: false)))
            #expect(sut.appLock.setAsideVaultCount == 0)
        }
    }

    /// A plain store that opened only after the vault was set aside doesn't hold the vault, so it isn't encrypted.
    @Test
    func setPassword_plainStoreSetAsideThisLaunch_isRefused() async throws {
        try await withTemporaryDirectory { directory in
            let sut = try await SUT(directory: directory, plainStoreOpenedNormally: false)

            await #expect(throws: VaultEncryptionError.plainStoreDidNotOpen) {
                try await sut.appLock.setPassword(Self.password)
            }
            #expect(sut.service.mode == .plain)
            #expect(!sut.appLock.isPasswordSet)
        }
    }

    /// Locking the app with the vault in the plain store leaves the store alone: the lock only hides it.
    @Test
    func lock_plainStore_leavesItOpen() async throws {
        try await withTemporaryDirectory { directory in
            let sut = try await SUT(directory: directory, isLockEnabled: true)
            await sut.appLock.unlock()
            let item = try await sut.insertItem()

            try await sut.lock()
            await sut.appLock.unlock()

            #expect(await !sut.session.isLocked)
            #expect(try await sut.itemIDs() == [item])
        }
    }

    /// The password was turned off, but the app stopped before it recorded that, and launch couldn't either: the
    /// state still says it's on. The password is refused before it's counted, the turn off is settled from the file,
    /// and the vault opens with the device key, as device authentication has passed. The lock then asks for device
    /// authentication alone.
    @Test
    func unlock_afterATurnOffThatWasntRecorded_opensWithTheDeviceKeyWithoutCounting() async throws {
        try await withTemporaryDirectory { directory in
            let keychain = try Keychain()
            let before = try await SUT(directory: directory, keychain: keychain)
            #expect(try await before.appLock.setPassword(Self.password))
            #expect(try await before.appLock.turnOffPassword(current: Self.password) == .accepted)
            try await before.lock()
            let stateFile = VaultStorageStateFile(directory: directory)
            var state = try stateFile.read()
            state.mode = .password
            state.transition = .turningOff
            try stateFile.write(state)

            let sut = try await SUT(directory: directory, keychain: keychain, mode: .password)
            #expect(sut.appLock.isPasswordSet)
            await sut.appLock.unlock()
            await sut.appLock.unlock(password: "anything")

            #expect(sut.appLock.state == .unlocked)
            #expect(!sut.appLock.isPasswordSet)
            #expect(sut.service.mode == .deviceKey)
            #expect(try stateFile.read() == VaultStorageState(mode: .deviceKey, unlockDeadline: .seconds(1)))
            #expect(try keychain.attempts.load() == nil)
        }
    }

    /// Turning the password back on couldn't record that either, but the device key opens nothing now, so the vault
    /// is in the password form: the new password unlocks it straight away.
    @Test
    func unlock_afterATurnOnThatWasntRecorded_unlocksWithTheNewPassword() async throws {
        try await withTemporaryDirectory { directory in
            let keychain = try Keychain()
            let before = try await SUT(directory: directory, keychain: keychain)
            #expect(try await before.appLock.setPassword(Self.password))
            #expect(try await before.appLock.turnOffPassword(current: Self.password) == .accepted)
            let staleKey = try #require(keychain.deviceKeys.key)
            #expect(try await before.appLock.setPassword(Self.newPassword))
            try await before.lock()
            try keychain.deviceKeys.restore(staleKey)
            let stateFile = VaultStorageStateFile(directory: directory)
            var state = try stateFile.read()
            state.mode = .deviceKey
            state.transition = .turningOn
            try stateFile.write(state)

            let sut = try await SUT(directory: directory, keychain: keychain, mode: .password)
            await sut.appLock.unlock()
            await sut.appLock.unlock(password: Self.newPassword)

            #expect(sut.appLock.state == .unlocked)
            #expect(sut.appLock.isPasswordSet)
        }
    }
}

// MARK: - Helpers

extension EncryptedVaultPasswordServiceTests {
    /// Where the app keeps the plain store (`VaultRoot.plainVaultStore`).
    @MainActor
    final class PlainStoreBox {
        var store: PersistedLocalVaultStore?
        /// Runs as a conversion lets go of the plain store, after it has committed and before it switches to the vault.
        var whileReleasing: (@MainActor () -> Void)?

        init(store: PersistedLocalVaultStore?) {
            self.store = store
        }

        func release() {
            store = nil
            whileReleasing?()
        }
    }

    /// The device's keychain and settings, in memory, so a relaunch finds what was there.
    @MainActor
    struct Keychain {
        let deviceKeys = InMemoryDeviceKeyStore()
        let attempts = LoggingAttemptStorage(log: SharedMutex([]))
        let wrapStamps = InMemoryWrapStampStorage()
        let secureStorage = InMemorySecureStorage()
        let attemptClock = FakeAppLockClock()
        let settings: AppLockSettingsStore

        init() throws {
            settings = try AppLockSettingsStore(userDefaults: .nonPersistent())
        }
    }

    /// The app's App Lock Password on a directory on disk, as the app makes it at launch.
    @MainActor
    struct SUT {
        let appLock: AppLockService
        let service: EncryptedVaultPasswordService
        let session: VaultStoreSession
        let keychain: Keychain
        let attemptStorage: LoggingAttemptStorage
        /// The plain store while the vault is in it, as `VaultRoot` keeps it: dropped once a conversion commits, and a
        /// fresh one after an erase.
        let plainStore: PlainStoreBox
        /// The unlock service's clock, which can hold an attempt at its deadline.
        let unlockClock: ManualUnlockClock

        /// - Parameter mode: How the vault is stored, as launch recovery left it. In the plain mode, the plain store
        ///   opens, and the session reads it; otherwise the session starts locked.
        init(
            directory: URL,
            keychain: Keychain? = nil,
            mode: VaultStorageState.Mode = .plain,
            isLockEnabled: Bool = false,
            plainStoreOpenedNormally: Bool = true,
        ) async throws {
            let keychain = try keychain ?? Keychain()
            let plainStore = try PlainStoreBox(
                store: mode == .plain
                    ? PersistedLocalVaultStoreFactory(storageDirectory: directory).makeVaultStoreOrThrow()
                    : nil,
            )
            let session = VaultStoreSession(target: plainStore.store.map { .plain($0) } ?? .locked)
            let unlockClock = ManualUnlockClock()
            let attemptCounter = AppLockPasswordAttemptCounter(storage: keychain.attempts, clock: keychain.attemptClock)
            let settings = keychain.settings
            let eraser = try VaultEraser(
                directory: directory,
                fileSystem: LiveSlotFileSystem(),
                session: session,
                secureStorage: keychain.secureStorage,
                attemptCounter: attemptCounter,
                wrapStamps: keychain.wrapStamps,
                deviceKeyStore: keychain.deviceKeys,
                appLockSettings: settings,
                defaults: Defaults(userDefaults: .nonPersistent()),
                temporaryDirectory: directory.appending(path: "tmp"),
                hooks: .init(
                    releasePlainStore: {},
                    clearCredentialIdentities: {},
                    reloadWidgets: {},
                    forgetVaultSettings: {},
                ),
                makePlainStore: {
                    try PersistedLocalVaultStoreFactory(storageDirectory: directory, recoveryMode: .openOnly)
                        .makeVaultStoreOrThrow()
                },
            )
            let wrapStamper = VaultDeviceWrapStamper.inMemory(storage: keychain.wrapStamps)
            let unlockService = VaultUnlockService(
                file: EncryptedVaultFile(directory: directory),
                session: session,
                attemptCounter: attemptCounter,
                deadlineStore: VaultStorageStateFile(directory: directory),
                deviceKeyStore: keychain.deviceKeys,
                purgeVaultContents: {},
                clock: unlockClock,
                availableMemory: { nil },
                wrapStamper: wrapStamper,
            )
            let archives = PersistedLocalVaultStoreArchives(storageDirectory: directory)
            let service = EncryptedVaultPasswordService(
                mode: mode,
                session: session,
                unlockService: unlockService,
                changeService: VaultPasswordChangeService(
                    directory: directory,
                    fileSystem: LiveSlotFileSystem(),
                    session: session,
                    unlockService: unlockService,
                    attemptCounter: attemptCounter,
                    deviceKeyStore: keychain.deviceKeys,
                    settings: settings,
                ),
                attemptCounter: attemptCounter,
                settings: settings,
                erase: {
                    plainStore.store = try await eraser.erase()
                },
                stateFile: VaultStorageStateFile(directory: directory),
                archives: archives,
                makeConverter: {
                    guard let store = plainStore.store else { return nil }
                    return VaultEncryptionConverter(
                        directory: directory,
                        fileSystem: LiveSlotFileSystem(),
                        plainStore: store,
                        plainStoreOpenedNormally: plainStoreOpenedNormally,
                        session: session,
                        archives: archives,
                        attemptCounter: attemptCounter,
                        hooks: .init(
                            releasePlainStore: {
                                await plainStore.release()
                            },
                            clearCredentialIdentities: {},
                            reloadWidgets: {},
                        ),
                        calibrate: {
                            AppLockKeyDerivationCalibration(
                                parameters: EncryptedVaultFixture.kdfParameters,
                                expectedDerivationDuration: .milliseconds(10),
                                unlockDeadline: .seconds(1),
                            )
                        },
                        wrapStamper: wrapStamper,
                        deviceBackupSettings: FakeDeviceBackupSettings(),
                    )
                },
            )
            if isLockEnabled {
                settings.isEnabled = true
            }
            settings.delay = .immediately
            appLock = AppLockService(
                settings: settings,
                authenticationService: DeviceAuthenticationService(policy: .alwaysAllow),
                passwordService: service,
                clock: keychain.attemptClock,
                purgeSensitiveData: {},
            )
            self.service = service
            self.session = session
            self.keychain = keychain
            self.plainStore = plainStore
            self.unlockClock = unlockClock
            attemptStorage = keychain.attempts
        }

        func insertItem() async throws -> Identifier<VaultItem> {
            try await session.insert(item: uniqueVaultItem().makeWritable())
        }

        func itemIDs() async throws -> [Identifier<VaultItem>] {
            try await session.retrieve(query: .init()).items.map(\.id)
        }

        /// Locks the app, as going to the background does, and waits for the vault to lock with it.
        func lock() async throws {
            appLock.scenePhaseDidChange(to: .background)
            await appLock.vaultLock?.value
            #expect(appLock.isLocked)
        }

        /// Locks, then unlocks with device authentication and `password`.
        func unlockAgain(with password: String) async throws {
            try await lock()
            await appLock.unlock()
            await appLock.unlock(password: password)
            #expect(appLock.state == .unlocked)
        }
    }
}
