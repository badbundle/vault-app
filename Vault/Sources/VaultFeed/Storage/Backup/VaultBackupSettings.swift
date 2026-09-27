import Foundation
import FoundationExtensions
import VaultKeygen

/// A vault's own backup settings: its backup password, the last backup made of it, how it's auto-backed up, and the
/// hint its PDF backups show.
///
/// Each vault has its own, so a duress vault never shows, uses, overwrites or cleans up the real vault's backups
/// (MANIFESTO C10), and the Backups page describes the vault that's open. The plain store's are device-wide, in the
/// keychain and `UserDefaults`, as they always were (`DeviceBackupSettings`). An encrypted vault keeps its own in its
/// payload (`VaultMetadata.settings`), and `OpenVaultBackupSettings` reads and writes whichever vault is open.
///
/// Every key is always written, `nil` as `null`, so the section has the same shape in every vault's payload.
public struct VaultBackupSettings: Equatable, Sendable {
    /// The backup password, or `nil` if none is set.
    public var backupPassword: StoredBackupPassword?
    /// The last time the vault was backed up, or its backup restored.
    public var lastBackupEvent: VaultBackupEvent?
    public var autoBackup: AutoBackupConfiguration
    /// The hint last printed in plain text on a PDF backup of the vault, or `nil` if none has been made, so the next
    /// one starts from the default.
    public var pdfUserHint: String?

    public init(
        backupPassword: StoredBackupPassword? = nil,
        lastBackupEvent: VaultBackupEvent? = nil,
        autoBackup: AutoBackupConfiguration = .init(),
        pdfUserHint: String? = nil,
    ) {
        self.backupPassword = backupPassword
        self.lastBackupEvent = lastBackupEvent
        self.autoBackup = autoBackup
        self.pdfUserHint = pdfUserHint
    }
}

extension VaultBackupSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case backupPassword, lastBackupEvent, autoBackup, pdfUserHint
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(backupPassword, forKey: .backupPassword)
        try container.encode(lastBackupEvent, forKey: .lastBackupEvent)
        try container.encode(autoBackup, forKey: .autoBackup)
        try container.encode(pdfUserHint, forKey: .pdfUserHint)
    }

    /// A key that's missing reads as its default, so fields can be added later.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        backupPassword = try container.decodeIfPresent(StoredBackupPassword.self, forKey: .backupPassword)
        lastBackupEvent = try container.decodeIfPresent(VaultBackupEvent.self, forKey: .lastBackupEvent)
        autoBackup = try container.decodeIfPresent(AutoBackupConfiguration.self, forKey: .autoBackup) ?? .init()
        pdfUserHint = try container.decodeIfPresent(String.self, forKey: .pdfUserHint)
    }
}

/// A backup password as a vault keeps it: the key derived from it, and when it was set.
public struct StoredBackupPassword: Equatable, Sendable {
    public var password: DerivedEncryptionKey
    /// When the password was set, if it's known.
    public var lastSetDate: Date?

    public init(password: DerivedEncryptionKey, lastSetDate: Date?) {
        self.password = password
        self.lastSetDate = lastSetDate
    }
}

extension StoredBackupPassword: Codable {
    private enum CodingKeys: String, CodingKey {
        case key, salt, keyDeriver, lastSetDate
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(password.key, forKey: .key)
        try container.encode(password.salt, forKey: .salt)
        try container.encode(password.keyDervier, forKey: .keyDeriver)
        try container.encode(lastSetDate, forKey: .lastSetDate)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        password = try DerivedEncryptionKey(
            key: container.decode(KeyData<32>.self, forKey: .key),
            salt: container.decode(Data.self, forKey: .salt),
            keyDervier: container.decode(VaultKeyDeriver.Signature.self, forKey: .keyDeriver),
        )
        lastSetDate = try container.decodeIfPresent(Date.self, forKey: .lastSetDate)
    }
}
