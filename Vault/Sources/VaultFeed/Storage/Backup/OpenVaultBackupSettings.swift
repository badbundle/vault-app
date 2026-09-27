import Foundation
import FoundationExtensions
import VaultKeygen

/// The backup settings of whichever vault is open: its backup password, its last backup event, its auto-backup
/// configuration and its PDF backup's hint.
///
/// - **The plain store's** are device-wide, where they've always been: the keychain and `UserDefaults`
///   (`DeviceBackupSettings`).
/// - **An unlocked encrypted vault's** are its own, in its payload (`VaultBackupSettings`), so a duress vault never
///   shows, uses, overwrites or cleans up the real vault's backups (MANIFESTO C10), and the Backups page describes the
///   vault that's open.
/// - **While the vault is locked** there are none: the password can't be read or set, and there's no last backup,
///   auto-backup or hint.
///
/// It's what the backup password store, the backup event logger, auto-backup and the PDF backup read and write
/// through, so none of them knows about vaults. Call `reload()` whenever the store session switches vault
/// (`VaultStoreSession.openVaultChanges()`). Until it's read them, it has none.
///
/// A change is only ever saved to the vault it was read from, and only while the session still has it open, for the
/// plain store as for an encrypted vault (`VaultStoreSession.whileOpen(_:_:)`). So once the session has locked, for
/// an erase or a conversion, or switched, a change meant for the vault that was open before is dropped, and can't put
/// back settings that were just deleted. Never log, print or measure which vault is open (MANIFESTO C3).
@MainActor
public final class OpenVaultBackupSettings {
    /// The vault that's open, and its settings.
    private struct Open {
        /// The plain store as the session opened it, or an encrypted vault.
        var vault: VaultStoreSession.OpenVault
        /// As last read from or saved to it. The plain store's backup password isn't here: it's only read from the
        /// keychain, which asks the user to authenticate.
        var settings: VaultBackupSettings
    }

    private let session: VaultStoreSession
    private let device: DeviceBackupSettings
    private let clock: any EpochClock
    private let authenticate: @Sendable () async throws -> Void
    private var open: Open?
    /// Goes up with every reload, so one that finishes after a later one started doesn't overwrite it, and settings
    /// read before it aren't saved into the vault it finds.
    public private(set) var vaultToken = 0
    /// Saves that haven't finished, which the next one waits for, so they're saved in order.
    private var pendingSave: Task<Void, Never>?

    /// - Parameters:
    ///   - session: The store session, whose open vault these are the settings of.
    ///   - device: The plain store's settings, on the device.
    ///   - authenticate: Asks the user to authenticate before an encrypted vault's backup password is read, as the
    ///     keychain does for the plain store's.
    public init(
        session: VaultStoreSession,
        device: DeviceBackupSettings,
        clock: any EpochClock,
        authenticate: @escaping @Sendable () async throws -> Void,
    ) {
        self.session = session
        self.device = device
        self.clock = clock
        self.authenticate = authenticate
    }

    /// Reads the settings of the vault that's open now.
    ///
    /// Until it's read them, it has none, so nothing is read from or saved to the vault that was open before.
    public func reload() async {
        vaultToken += 1
        let token = vaultToken
        open = nil
        let vault = await session.openVault
        let settings: VaultBackupSettings? = switch vault {
        case .plain: device.read(backupPassword: nil)
        case let .encrypted(store): await store.backupSettings
        case .locked: nil
        }
        // A later reload knows better.
        guard token == vaultToken else { return }
        open = settings.map { Open(vault: vault, settings: $0) }
    }

    /// Whether the vault `token` identifies is still the open one.
    public func isOpen(_ token: Int) async -> Bool {
        guard token == vaultToken, let expected = open?.vault else { return false }
        let current = await session.openVault
        // Checked again after the wait, and nothing else runs on the main actor before the caller carries on.
        return token == vaultToken && current.isSame(as: expected)
    }

    /// Runs `body` while `vault` is still the open one, after any save still underway.
    ///
    /// The task throws `VaultStoreSessionError.locked` if the vault isn't open any more, or what `body` threw.
    private func whileOpen(
        _ vault: VaultStoreSession.OpenVault,
        _ body: @escaping @Sendable () async throws -> Void,
    ) -> Task<Void, any Error> {
        let previous = pendingSave
        let session = session
        let task = Task {
            await previous?.value
            try await session.whileOpen(vault, body)
        }
        pendingSave = Task { _ = await task.result }
        return task
    }

    /// Saves a change to `vault`'s settings, while it's still the open one: to its slot for an encrypted vault, or to
    /// `UserDefaults` for the plain store.
    private func save(
        _ update: @escaping @Sendable (inout VaultBackupSettings) -> Void,
        to vault: VaultStoreSession.OpenVault,
    ) -> Task<Void, any Error> {
        let device = device
        return whileOpen(vault) {
            switch vault {
            case let .encrypted(store):
                try await store.updateBackupSettings(update)
            case .plain:
                try await MainActor.run {
                    var settings = device.read(backupPassword: nil)
                    update(&settings)
                    try device.save(settings)
                }
            case .locked:
                throw VaultStoreSessionError.locked
            }
        }
    }

    /// Makes a change to `vault`'s settings in memory, if it's still the open vault.
    private func apply(_ update: (inout VaultBackupSettings) -> Void, to vault: VaultStoreSession.OpenVault) {
        guard var open, open.vault.isSame(as: vault) else { return }
        update(&open.settings)
        self.open = open
    }

    /// The vault that's open, if `token` still identifies it.
    private func openVault(for token: Int) throws -> VaultStoreSession.OpenVault {
        guard token == vaultToken, let open else { throw VaultStoreSessionError.locked }
        return open.vault
    }
}

// MARK: - Backup password

extension OpenVaultBackupSettings: BackupPasswordStore {
    public func fetchPassword() async throws -> DerivedEncryptionKey? {
        switch open?.vault {
        case .plain:
            return try await device.passwordStore.fetchPassword()
        case .encrypted:
            guard let stored = open?.settings.backupPassword else { return nil }
            try await authenticate()
            return stored.password
        case .locked, nil:
            throw VaultStoreSessionError.locked
        }
    }

    public func set(password: DerivedEncryptionKey) async throws {
        switch open?.vault {
        case let .plain(opening):
            let passwordStore = device.passwordStore
            try await whileOpen(.plain(opening)) {
                try await passwordStore.set(password: password)
            }.value
        case let .encrypted(store):
            let stored = StoredBackupPassword(password: password, lastSetDate: clock.currentDate)
            let update: @Sendable (inout VaultBackupSettings) -> Void = { $0.backupPassword = stored }
            try await save(update, to: .encrypted(store)).value
            apply(update, to: .encrypted(store))
        case .locked, nil:
            throw VaultStoreSessionError.locked
        }
    }

    public func removePassword() async throws {
        switch open?.vault {
        case let .plain(opening):
            let passwordStore = device.passwordStore
            try await whileOpen(.plain(opening)) {
                try await passwordStore.removePassword()
            }.value
        case let .encrypted(store):
            let update: @Sendable (inout VaultBackupSettings) -> Void = { $0.backupPassword = nil }
            try await save(update, to: .encrypted(store)).value
            apply(update, to: .encrypted(store))
        case .locked, nil:
            throw VaultStoreSessionError.locked
        }
    }

    public func fetchPasswordMetadata() async throws -> BackupPasswordMetadata? {
        switch open?.vault {
        case .plain:
            try await device.passwordStore.fetchPasswordMetadata()
        case .encrypted:
            open?.settings.backupPassword.map { BackupPasswordMetadata(lastSetDate: $0.lastSetDate) }
        case .locked, nil:
            throw VaultStoreSessionError.locked
        }
    }
}

// MARK: - Last backup event

extension OpenVaultBackupSettings: BackupEventStorage {
    public func lastBackupEvent() -> VaultBackupEvent? {
        open?.settings.lastBackupEvent
    }

    /// Saved in the background: it's in memory straight away. If saving fails, the event is no worse off than one
    /// that was never logged.
    public func saveLastBackupEvent(_ event: VaultBackupEvent, for token: Int) throws {
        let vault = try openVault(for: token)
        let update: @Sendable (inout VaultBackupSettings) -> Void = { $0.lastBackupEvent = event }
        apply(update, to: vault)
        _ = save(update, to: vault)
    }
}

// MARK: - Auto-backup configuration

extension OpenVaultBackupSettings: AutoBackupConfigurationStorage {
    public var isDeviceWide: Bool {
        if case .plain = open?.vault {
            true
        } else {
            false
        }
    }

    public func autoBackupConfiguration() -> AutoBackupConfiguration? {
        open?.settings.autoBackup
    }

    public func saveAutoBackupConfiguration(_ configuration: AutoBackupConfiguration, for token: Int) async throws {
        let vault = try openVault(for: token)
        let update: @Sendable (inout VaultBackupSettings) -> Void = { $0.autoBackup = configuration }
        try await save(update, to: vault).value
        apply(update, to: vault)
    }
}

// MARK: - PDF backup's hint

extension OpenVaultBackupSettings: BackupPDFHintStorage {
    public func pdfUserHint() -> String? {
        open?.settings.pdfUserHint
    }

    /// Saved in the background, like an event: it's in memory straight away.
    public func savePDFUserHint(_ hint: String, for token: Int) throws {
        let vault = try openVault(for: token)
        let update: @Sendable (inout VaultBackupSettings) -> Void = { $0.pdfUserHint = hint }
        apply(update, to: vault)
        _ = save(update, to: vault)
    }
}
