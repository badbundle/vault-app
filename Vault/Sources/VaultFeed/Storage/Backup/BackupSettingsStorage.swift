import Foundation
import FoundationExtensions
import VaultCore

/// Where the last backup event is kept: `UserDefaults` for the plain store, or the open vault's own settings
/// (`OpenVaultBackupSettings`).
@MainActor
public protocol BackupEventStorage: AnyObject {
    /// Identifies the vault the last backup event is read from now. It changes whenever the open vault does.
    var vaultToken: Int { get }
    func lastBackupEvent() -> VaultBackupEvent?
    /// Saves the event as the last backup of the vault `token` identifies.
    ///
    /// - Throws: If that vault isn't open any more, or it couldn't be saved.
    func saveLastBackupEvent(_ event: VaultBackupEvent, for token: Int) throws
}

/// Where the auto-backup configuration is kept: `UserDefaults` for the plain store, or the open vault's own settings
/// (`OpenVaultBackupSettings`).
///
/// A configuration read from one vault must only ever be saved into that vault, and a backup made for it must stop
/// once another vault opens. So each read comes with a token for the vault it was read from.
@MainActor
public protocol AutoBackupConfigurationStorage: AnyObject {
    /// Identifies the vault `autoBackupConfiguration()` reads from now. It changes whenever the open vault does.
    var vaultToken: Int { get }
    /// Whether the configuration is the plain store's, device-wide, rather than an encrypted vault's own.
    var isDeviceWide: Bool { get }
    /// The configuration saved, or `nil` if there isn't one, or no vault is open.
    func autoBackupConfiguration() -> AutoBackupConfiguration?
    /// Whether the vault `token` identifies is still the open one. It asks the store session, so it's right as soon
    /// as the session switches, before anything has reloaded.
    func isOpen(_ token: Int) async -> Bool
    /// Saves the configuration into the vault `token` identifies.
    ///
    /// - Throws: If that vault isn't open any more, or it couldn't be saved.
    func saveAutoBackupConfiguration(_ configuration: AutoBackupConfiguration, for token: Int) async throws
}

/// Where the hint a PDF backup shows in plain text is kept: `UserDefaults` for the plain store, or the open vault's own
/// settings (`OpenVaultBackupSettings`).
@MainActor
public protocol BackupPDFHintStorage: AnyObject {
    /// Identifies the vault `pdfUserHint()` reads from now. It changes whenever the open vault does.
    var vaultToken: Int { get }
    /// The hint last used, or `nil` if there isn't one, or no vault is open.
    func pdfUserHint() -> String?
    /// Saves the hint into the vault `token` identifies.
    ///
    /// - Throws: If that vault isn't open any more, or it couldn't be saved.
    func savePDFUserHint(_ hint: String, for token: Int) throws
}

// MARK: - UserDefaults

/// The plain store's backup settings, device-wide, where they've always been. For tests and previews: the app keeps
/// them through `OpenVaultBackupSettings`, which knows when the plain store is open.
extension Defaults: BackupEventStorage, AutoBackupConfigurationStorage, BackupPDFHintStorage {
    static let lastBackupEventKey = Key<VaultBackupEvent>(VaultIdentifiers.Backup.lastBackupEvent)
    static let autoBackupConfigurationKey = Key<AutoBackupConfiguration>(VaultIdentifiers.AutoBackup.configuration)
    static let pdfUserHintKey = Key<String>(VaultIdentifiers.Preferences.PDF.userHint)

    /// Always the same: there's only ever the one vault.
    public var vaultToken: Int {
        0
    }

    public var isDeviceWide: Bool {
        true
    }

    public func lastBackupEvent() -> VaultBackupEvent? {
        get(for: Self.lastBackupEventKey)
    }

    public func saveLastBackupEvent(_ event: VaultBackupEvent, for _: Int) throws {
        try set(event, for: Self.lastBackupEventKey)
    }

    public func autoBackupConfiguration() -> AutoBackupConfiguration? {
        get(for: Self.autoBackupConfigurationKey)
    }

    public func isOpen(_: Int) async -> Bool {
        true
    }

    public func saveAutoBackupConfiguration(_ configuration: AutoBackupConfiguration, for _: Int) async throws {
        try set(configuration, for: Self.autoBackupConfigurationKey)
    }

    public func pdfUserHint() -> String? {
        get(for: Self.pdfUserHintKey)
    }

    public func savePDFUserHint(_ hint: String, for _: Int) throws {
        try set(hint, for: Self.pdfUserHintKey)
    }
}
