import Combine
import Foundation

/// Current status of the auto-backup service.
public enum AutoBackupStatus: Equatable, Sendable {
    /// Auto-backup is disabled.
    case disabled

    /// Auto-backup is idle, waiting for changes.
    case idle

    /// A backup is currently in progress.
    case backingUp(AutoBackupRun)

    /// Cleaning up old backups.
    case cleaningUp

    /// An error occurred during the last backup attempt.
    case error(AutoBackupError)

    /// Last backup completed successfully.
    case completed(Date)
}

/// Service that orchestrates automated backups.
///
/// @mockable
@MainActor
public protocol AutoBackupService: Sendable {
    /// Current status of the auto-backup service.
    var status: AutoBackupStatus { get }

    /// Publisher that emits status changes.
    var statusPublisher: AnyPublisher<AutoBackupStatus, Never> { get }

    /// Current configuration.
    var configuration: AutoBackupConfiguration { get }

    /// Publisher that emits configuration changes.
    var configurationPublisher: AnyPublisher<AutoBackupConfiguration, Never> { get }

    /// Available storage providers.
    var availableProviders: [any BackupStorageProvider] { get }

    /// The currently selected provider, if any.
    var selectedProvider: (any BackupStorageProvider)? { get }

    /// Enable or disable auto-backup.
    func setEnabled(_ enabled: Bool) async

    /// Select a storage provider by ID.
    func selectProvider(id: String) async

    /// Set the retention period.
    func setRetention(_ retention: AutoBackupRetention) async

    /// Trigger a backup if there are changes since the last backup.
    func triggerBackupIfNeeded() async

    /// Force a backup regardless of whether there are changes.
    func forceBackup() async

    /// Clean up old backups based on retention settings.
    func cleanupOldBackups() async

    /// Save the current provider configurations to persistent storage.
    /// Call this after configuring a provider externally.
    func saveProviderConfiguration() async

    /// Notify the service that vault data has changed.
    /// This triggers a debounced backup if auto-backup is enabled.
    func notifyDataChanged()
}
