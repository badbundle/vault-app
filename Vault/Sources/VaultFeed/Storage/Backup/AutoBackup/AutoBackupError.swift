import Foundation

/// Errors that can occur during auto-backup operations.
public enum AutoBackupError: Error, Equatable, Sendable {
    /// No storage provider has been selected.
    case noProviderSelected

    /// The selected provider is not configured (e.g., no folder selected).
    case providerNotConfigured

    /// The provider is not available (e.g., iCloud not signed in).
    case providerUnavailable(reason: String)

    /// Access to the backup location was denied.
    case accessDenied

    /// The backup password has not been set.
    case backupPasswordNotSet

    /// Failed to generate the backup PDF.
    case pdfGenerationFailed(reason: String)

    /// Failed to write the backup file.
    case writeFailed(reason: String)

    /// A file with the backup's name is there already. It's never replaced: it could be another vault's backup.
    case backupFileExists

    /// Failed to delete old backup files.
    case cleanupFailed(reason: String)

    /// Network is unavailable for cloud providers.
    case networkUnavailable

    /// Storage is full.
    case storageFull

    /// An unknown error occurred.
    case unknown(reason: String)
}

extension AutoBackupError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .noProviderSelected:
            "No backup destination selected"
        case .providerNotConfigured:
            "Backup destination not configured"
        case let .providerUnavailable(reason):
            reason
        case .accessDenied:
            "Access to backup location denied"
        case .backupPasswordNotSet:
            "Backup password not set"
        case let .pdfGenerationFailed(reason):
            "Failed to create backup: \(reason)"
        case let .writeFailed(reason):
            "Failed to save backup: \(reason)"
        case .backupFileExists:
            "A backup with the same name is already there"
        case let .cleanupFailed(reason):
            "Failed to clean up old backups: \(reason)"
        case .networkUnavailable:
            "Network unavailable"
        case .storageFull:
            "Storage is full"
        case let .unknown(reason):
            reason
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .noProviderSelected:
            "Select a backup destination in settings."
        case .providerNotConfigured:
            "Configure the backup destination."
        case .providerUnavailable:
            "Check your account settings and try again."
        case .accessDenied:
            "Please reselect the backup folder."
        case .backupPasswordNotSet:
            "Create a backup password first."
        case .pdfGenerationFailed, .writeFailed, .backupFileExists, .unknown:
            "Please try again later."
        case .cleanupFailed:
            "You may need to manually delete old backups."
        case .networkUnavailable:
            "Connect to the internet and try again."
        case .storageFull:
            "Free up storage space and try again."
        }
    }
}
