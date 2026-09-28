import Foundation
import FoundationExtensions
import TestHelpers
import Testing
@testable import VaultFeed

/// The App Lock Password with the key derivation the app ships: Argon2id with 64 MiB, and passes calibrated on this
/// device. It takes seconds and the memory, so this is the only test that does: every other one uses cheap parameters
/// (`EncryptedVaultFixture.kdfParameters`).
@MainActor
@Suite(.serialized)
struct AppLockProductionKeyDerivationTests {
    @Test(.timeLimit(.minutes(2)))
    func password_withTheShippedKeyDerivation_opensTheVaultAndRefusesAWrongOne() async throws {
        try await withTemporaryDirectory { directory in
            let store = try PersistedLocalVaultStoreFactory(storageDirectory: directory).makeVaultStoreOrThrow()
            let session = VaultStoreSession(target: .plain(store))
            let item = try await session.insert(item: uniqueVaultItem().makeWritable())
            let attemptCounter = AppLockPasswordAttemptCounter(
                storage: LoggingAttemptStorage(log: SharedMutex([])),
                clock: FakeAppLockClock(),
            )
            let wrapStamper = VaultDeviceWrapStamper.inMemory(storage: InMemoryWrapStampStorage())
            let converter = VaultEncryptionConverter(
                directory: directory,
                fileSystem: LiveSlotFileSystem(),
                plainStore: store,
                plainStoreOpenedNormally: true,
                session: session,
                archives: PersistedLocalVaultStoreArchives(storageDirectory: directory),
                attemptCounter: attemptCounter,
                hooks: .init(releasePlainStore: {}, clearCredentialIdentities: {}, reloadWidgets: {}),
                calibrate: { try AppLockKeyDerivationCalibrator().calibrate() },
                wrapStamper: wrapStamper,
                deviceBackupSettings: FakeDeviceBackupSettings(),
            )
            let unlockService = VaultUnlockService(
                file: EncryptedVaultFile(directory: directory),
                session: session,
                attemptCounter: attemptCounter,
                deadlineStore: VaultStorageStateFile(directory: directory),
                deviceKeyStore: InMemoryDeviceKeyStore(),
                purgeVaultContents: {},
                availableMemory: { nil },
                wrapStamper: wrapStamper,
            )

            try await converter.encrypt(password: "correct horse", deletingArchives: false)
            let read = try EncryptedVaultFile(directory: directory).readHeader()
            let header = try #require(read).header
            #expect(header.kdfParameters.memoryKiB == AppLockKeyDerivation.memoryKiB)
            #expect(AppLockKeyDerivation.passesRange.contains(header.kdfParameters.iterations))
            await unlockService.lock()

            #expect(try await unlockService.unlock(password: "wrong password") == .wrongPassword(
                reachesEraseThreshold: false,
            ))
            #expect(await session.isLocked)
            #expect(try await unlockService.unlock(password: "correct horse") == .unlocked)
            #expect(try await session.retrieve(query: .init()).items.map(\.id) == [item])
        }
    }
}
