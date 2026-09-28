import Foundation

public enum BackupImportContext: Equatable {
    case toEmptyVault
    case merge
    case override
}

extension BackupImportContext {
    public var readyToImportTitle: String {
        switch self {
        case .toEmptyVault:
            "Ready to Import"
        case .merge:
            "Ready to Merge"
        case .override:
            "Replace Your Vault?"
        }
    }

    public var readyToImportDescription: String {
        switch self {
        case .toEmptyVault:
            "Everything in the backup will be added to your vault."
        case .merge:
            "Where an item is in both, the newer version is kept."
        case .override:
            "Everything on this device that isn't in the backup will be deleted."
        }
    }

    /// The button that imports the backup, named for what it does to the vault.
    public var importActionTitle: String {
        switch self {
        case .toEmptyVault:
            "Import"
        case .merge:
            "Merge"
        case .override:
            "Replace Vault"
        }
    }

    public var importingMessage: String {
        switch self {
        case .toEmptyVault:
            "Importing the backup."
        case .merge:
            "Merging the backup into your vault."
        case .override:
            "Replacing your vault with the backup."
        }
    }

    public var importedTitle: String {
        switch self {
        case .toEmptyVault:
            "Backup Imported"
        case .merge:
            "Backup Merged"
        case .override:
            "Vault Replaced"
        }
    }

    public var importedDescription: String {
        switch self {
        case .toEmptyVault:
            "Everything in the backup is now in your vault."
        case .merge:
            "The backup's items are in your vault, with the newer version of each kept."
        case .override:
            "Your vault now has only what was in the backup."
        }
    }
}
