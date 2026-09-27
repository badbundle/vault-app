import Foundation

/// Retention period options for auto-backups.
public enum AutoBackupRetention: Int, CaseIterable, Codable, Sendable {
    case days7 = 7
    case days30 = 30
    case year1 = 365
    case forever = 0

    public var localizedTitle: String {
        switch self {
        case .days7: "7 days"
        case .days30: "30 days"
        case .year1: "1 year"
        case .forever: "Forever"
        }
    }

    /// Whether old backups should be cleaned up for this retention setting.
    public var shouldCleanup: Bool {
        self != .forever
    }
}

/// Configuration for automated backups.
public struct AutoBackupConfiguration: Codable, Equatable, Sendable {
    /// Whether auto-backup is enabled.
    public var isEnabled: Bool

    /// How many days of backup history to retain.
    public var retentionDays: AutoBackupRetention

    /// The ID of the active storage provider.
    public var providerID: String?

    /// Provider-specific configuration data, keyed by provider ID.
    public var providerConfigs: [String: Data]

    /// Hash of the last successful auto-backup payload.
    public var lastBackupHash: String?

    /// Date of the last successful auto-backup.
    public var lastBackupDate: Date?

    /// The names of the backup files this vault's auto-backup wrote and hasn't cleaned up yet.
    ///
    /// Cleaning up only ever deletes these, so a vault never deletes a backup it didn't write: another vault's, one
    /// written before these were recorded, or one the user put there (MANIFESTO C10).
    public var backupFilenames: [String]

    /// Whether `backupFilenames` has every backup file the configuration's auto-backup is to clean up.
    ///
    /// A configuration saved before the files were recorded hasn't. For the plain store, auto-backup then seeds them
    /// once from the folder, with every file the cleanup it used to do would have deleted (`AutoBackupServiceImpl`).
    public var backupFilenamesAreComplete: Bool

    /// Creates a default configuration with auto-backup disabled.
    public init() {
        isEnabled = false
        retentionDays = .days30
        providerID = nil
        providerConfigs = [:]
        lastBackupHash = nil
        lastBackupDate = nil
        backupFilenames = []
        backupFilenamesAreComplete = true
    }

    public init(
        isEnabled: Bool,
        retentionDays: AutoBackupRetention,
        providerID: String?,
        providerConfigs: [String: Data],
        lastBackupHash: String?,
        lastBackupDate: Date?,
        backupFilenames: [String] = [],
        backupFilenamesAreComplete: Bool = true,
    ) {
        self.isEnabled = isEnabled
        self.retentionDays = retentionDays
        self.providerID = providerID
        self.providerConfigs = providerConfigs
        self.lastBackupHash = lastBackupHash
        self.lastBackupDate = lastBackupDate
        self.backupFilenames = backupFilenames
        self.backupFilenamesAreComplete = backupFilenamesAreComplete
    }
}

extension AutoBackupConfiguration {
    private enum CodingKeys: String, CodingKey {
        case isEnabled, retentionDays, providerID, providerConfigs, lastBackupHash, lastBackupDate, backupFilenames
        case backupFilenamesAreComplete
    }

    /// Every key is written, `nil` as `null`, so the configuration has the same shape in every vault's payload,
    /// whatever it holds.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(retentionDays, forKey: .retentionDays)
        try container.encode(providerID, forKey: .providerID)
        try container.encode(providerConfigs, forKey: .providerConfigs)
        try container.encode(lastBackupHash, forKey: .lastBackupHash)
        try container.encode(lastBackupDate, forKey: .lastBackupDate)
        try container.encode(backupFilenames, forKey: .backupFilenames)
        try container.encode(backupFilenamesAreComplete, forKey: .backupFilenamesAreComplete)
    }

    /// A key that's missing, as it is in a configuration saved before it was added, reads as its default, except that
    /// such a configuration hasn't recorded its backup files.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AutoBackupConfiguration()
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? defaults.isEnabled
        retentionDays = try container.decodeIfPresent(AutoBackupRetention.self, forKey: .retentionDays)
            ?? defaults.retentionDays
        providerID = try container.decodeIfPresent(String.self, forKey: .providerID)
        providerConfigs = try container.decodeIfPresent([String: Data].self, forKey: .providerConfigs) ?? [:]
        lastBackupHash = try container.decodeIfPresent(String.self, forKey: .lastBackupHash)
        lastBackupDate = try container.decodeIfPresent(Date.self, forKey: .lastBackupDate)
        backupFilenames = try container.decodeIfPresent([String].self, forKey: .backupFilenames) ?? []
        backupFilenamesAreComplete = try container.decodeIfPresent(Bool.self, forKey: .backupFilenamesAreComplete)
            ?? false
    }
}
