import CryptoEngine
import Foundation
import VaultCore

/// A record of a backup or sync performed by the user relative to this device.
///
/// Because there's no cloud sync, each individual device will have it's own state in regards to the backup state.
///
/// It doesn't need to be encrypted or protected as it doesn't contain any sensitive data.
public struct VaultBackupEvent: Equatable, Hashable, Codable, Sendable {
    /// The timestamp associated with the backup.
    ///
    /// This is the actual date that the backup was created, not the date that the backup was imported or exported.
    public var backupDate: Date
    /// The date that this backup event was performed (import/export).
    public var eventDate: Date
    /// The action that was taken on this backup to reach the current state.
    public var kind: Kind
    /// Hash of all deterministic data that was backed up (application payload).
    ///
    /// This hash is used to check what data was actually backed up, so no random data or timestamps should be
    /// included in this hash.
    public var payloadHash: Digest<VaultApplicationPayload>.SHA256

    public init(backupDate: Date, eventDate: Date, kind: Kind, payloadHash: Digest<VaultApplicationPayload>.SHA256) {
        self.backupDate = backupDate
        self.eventDate = eventDate
        self.kind = kind
        self.payloadHash = payloadHash
    }
}

extension VaultBackupEvent {
    /// How far behind a backup is, in the steps the Backups page warns at.
    public enum Staleness: Equatable, Hashable, Sendable {
        /// Made within the last week.
        case recent
        /// Made within the last 30 days.
        case stale
        /// Made 30 or more days ago.
        case veryStale
    }

    /// How stale this backup is at `date`, going by when it was made rather than when it was
    /// exported or imported.
    public func staleness(at date: Date, calendar: Calendar = .current) -> Staleness {
        let days = calendar.dateComponents([.day], from: backupDate, to: date).day ?? .max
        return if days < 7 {
            .recent
        } else if days < 30 {
            .stale
        } else {
            .veryStale
        }
    }
}

extension VaultBackupEvent {
    public enum Kind: Equatable, Hashable, Sendable, Codable {
        case exportedToPDF
        case importedToPDF
        case exportedToDevice
        case importedFromDevice
        case exportedToAutoBackup(providerID: String)

        public var localizedTitle: String {
            switch self {
            case .exportedToPDF: "Exported to PDF"
            case .importedToPDF: "Imported from PDF"
            case .exportedToDevice: "Transferred to Device"
            case .importedFromDevice: "Imported from Device"
            case .exportedToAutoBackup: "Auto-Backup"
            }
        }

        /// Custom Codable for backwards compatibility
        private enum CodingKeys: String, CodingKey {
            case type
            case providerID
        }

        private enum LegacyType: String, Codable {
            case exportedToPDF = "EXPORT_TO_PDF"
            case importedToPDF = "IMPORT_FROM_PDF"
            case exportedToDevice = "EXPORT_TO_DEVICE"
            case importedFromDevice = "IMPORT_FROM_DEVICE"
            case exportedToAutoBackup = "EXPORT_TO_AUTO_BACKUP"
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(LegacyType.self, forKey: .type)
            switch type {
            case .exportedToPDF:
                self = .exportedToPDF
            case .importedToPDF:
                self = .importedToPDF
            case .exportedToDevice:
                self = .exportedToDevice
            case .importedFromDevice:
                self = .importedFromDevice
            case .exportedToAutoBackup:
                let providerID = try container.decode(String.self, forKey: .providerID)
                self = .exportedToAutoBackup(providerID: providerID)
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .exportedToPDF:
                try container.encode(LegacyType.exportedToPDF, forKey: .type)
            case .importedToPDF:
                try container.encode(LegacyType.importedToPDF, forKey: .type)
            case .exportedToDevice:
                try container.encode(LegacyType.exportedToDevice, forKey: .type)
            case .importedFromDevice:
                try container.encode(LegacyType.importedFromDevice, forKey: .type)
            case let .exportedToAutoBackup(providerID):
                try container.encode(LegacyType.exportedToAutoBackup, forKey: .type)
                try container.encode(providerID, forKey: .providerID)
            }
        }
    }
}
