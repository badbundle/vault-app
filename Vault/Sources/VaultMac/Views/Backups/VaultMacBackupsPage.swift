import Foundation
import VaultCore
import VaultFeed
import VaultKeygen
import VaultSettings

/// The pages of the Backups area, listed in the window's middle column.
enum VaultMacBackupsPage: String, CaseIterable, Identifiable {
    case autoBackup
    case keepABackup
    case transfer
    case restore
    case password

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .autoBackup: "Auto-Backup"
        case .keepABackup: "Keep a Backup"
        case .transfer: "Move to Another Device"
        case .restore: "Restore"
        case .password: "Backup Password"
        }
    }

    var systemImage: String {
        switch self {
        case .autoBackup: "arrow.clockwise.icloud"
        case .keepABackup: "doc.badge.arrow.up"
        case .transfer: "qrcode"
        case .restore: "square.and.arrow.down"
        case .password: "lock.shield"
        }
    }
}

/// What the Backups pages use: the shared backup services, as `VaultMacRoot` has them, or a test's.
@MainActor
struct VaultMacBackupServices {
    var dataModel: VaultDataModel
    var authentication: DeviceAuthenticationService
    var keyDeriverFactory: any VaultKeyDeriverFactory
    var clock: any EpochClock
    var intervalTimer: any IntervalTimer
    var defaults: Defaults
    var hintStorage: any BackupPDFHintStorage
    var backupEventLogger: any BackupEventLogger
    var autoBackupService: any AutoBackupService
    var encryptedVaultDecoder: any EncryptedVaultDecoder<KeyData<32>>
    var fileManager: FileManager = .default

    static var live: VaultMacBackupServices {
        VaultMacBackupServices(
            dataModel: VaultMacRoot.vaultDataModel,
            authentication: VaultMacRoot.deviceAuthenticationService,
            keyDeriverFactory: VaultMacRoot.vaultKeyDeriverFactory,
            clock: VaultMacRoot.clock,
            intervalTimer: VaultMacRoot.timer,
            defaults: VaultMacRoot.defaults,
            hintStorage: VaultMacRoot.openVaultBackupSettings,
            backupEventLogger: VaultMacRoot.backupEventLogger,
            autoBackupService: VaultMacRoot.autoBackupService,
            encryptedVaultDecoder: VaultMacRoot.encryptedVaultDecoder,
        )
    }
}
