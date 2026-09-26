import Foundation
import FoundationExtensions
import VaultFeed

/// Object to retain and share non-observable dependencies across views.
///
/// Not all objects make sense as SwiftUI @Environment objects, but might still be needed in places.
/// This is a good place to store and subsequently inject them.
@Observable
public final class VaultInjector {
    public let clock: any EpochClock
    public let intervalTimer: any IntervalTimer
    public let backupEventLogger: any BackupEventLogger
    public let vaultKeyDeriverFactory: any VaultKeyDeriverFactory
    public let encryptedVaultDecoder: any EncryptedVaultDecoder<KeyData<32>>
    public let autoBackupService: any AutoBackupService
    public let defaults: Defaults
    public let fileManager: FileManager
    /// Vaults set aside because they couldn't be opened.
    public let vaultStoreArchives: any VaultStoreArchiving

    public init(
        clock: any EpochClock,
        intervalTimer: any IntervalTimer,
        backupEventLogger: any BackupEventLogger,
        vaultKeyDeriverFactory: any VaultKeyDeriverFactory,
        encryptedVaultDecoder: any EncryptedVaultDecoder<KeyData<32>>,
        autoBackupService: any AutoBackupService,
        defaults: Defaults,
        fileManager: FileManager,
        vaultStoreArchives: any VaultStoreArchiving = NoVaultStoreArchives(),
    ) {
        self.clock = clock
        self.intervalTimer = intervalTimer
        self.backupEventLogger = backupEventLogger
        self.vaultKeyDeriverFactory = vaultKeyDeriverFactory
        self.encryptedVaultDecoder = encryptedVaultDecoder
        self.autoBackupService = autoBackupService
        self.defaults = defaults
        self.fileManager = fileManager
        self.vaultStoreArchives = vaultStoreArchives
    }
}
