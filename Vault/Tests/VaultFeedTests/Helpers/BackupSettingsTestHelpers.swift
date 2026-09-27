import Foundation
import FoundationExtensions
import VaultCore
@testable import VaultFeed

/// The plain store's backup settings on a device in memory: the keychain's backup password and `UserDefaults`, and
/// how many times the user was asked to authenticate for an encrypted vault's password.
@MainActor
struct TestDeviceBackupSettings {
    let secureStorage = InMemorySecureStorage(canReadAttributesWithoutAuthentication: true)
    let passwordStore: BackupPasswordStoreImpl
    let defaults: Defaults
    let device: DeviceBackupSettings
    let authentications = SharedMutex(0)
    let authenticate: @Sendable () async throws -> Void

    init(authenticationError: (any Error)? = nil, clock: any EpochClock = EpochClockMock(currentTime: 5000)) throws {
        passwordStore = BackupPasswordStoreImpl(secureStorage: secureStorage, clock: clock)
        defaults = try Defaults(userDefaults: testUserDefaults())
        device = DeviceBackupSettings(passwordStore: passwordStore, secureStorage: secureStorage, defaults: defaults)
        let authentications = authentications
        authenticate = {
            authentications.modify { $0 += 1 }
            if let authenticationError {
                throw authenticationError
            }
        }
    }
}

extension OpenVaultBackupSettings {
    /// Settings following `session`, with the plain store's on `device`, in memory.
    @MainActor
    static func inMemory(
        session: VaultStoreSession,
        device: TestDeviceBackupSettings? = nil,
        clock: any EpochClock = EpochClockMock(currentTime: 5000),
    ) throws -> OpenVaultBackupSettings {
        let device = try device ?? TestDeviceBackupSettings()
        return OpenVaultBackupSettings(
            session: session,
            device: device.device,
            clock: clock,
            authenticate: device.authenticate,
        )
    }
}

extension VaultRecordState {
    /// An empty vault with these backup settings.
    static func empty(with settings: VaultBackupSettings) -> VaultRecordState {
        VaultRecordState(items: [], tags: [], vault: VaultMetadata(settings: settings))
    }
}

extension EncryptedVaultFixture {
    /// Two vaults in one file, in slots 2 and 9, each having written a backup of its own: `first.pdf` and
    /// `second.pdf`.
    static func twoVaults() async throws -> (EncryptedVaultFixture, EncryptedVaultFixture) {
        let first = try EncryptedVaultFixture(
            state: .empty(with: VaultBackupSettings(autoBackup: .written(["first.pdf"]))),
            slotIndex: 2,
        )
        let second = try await first.addingVault(
            inSlot: 9,
            state: .empty(with: VaultBackupSettings(autoBackup: .written(["second.pdf"]))),
        )
        return (first, second)
    }
}
