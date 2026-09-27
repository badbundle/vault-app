import Combine
import CryptoEngine
import Foundation
import FoundationExtensions
import VaultCore

/// Logs backup events so the user has visibility when the last one was performed.
///
/// Each event goes into the vault a backup was made of, which the caller identifies with `vaultToken`, read when the
/// backup started. If that vault isn't open any more when it finishes, the event is dropped: it's never logged into
/// another vault (MANIFESTO C10).
///
/// @mockable
@MainActor
public protocol BackupEventLogger: Sendable {
    /// Identifies the vault that's open now. Read it when a backup starts, and log the backup with it.
    var vaultToken: Int { get }
    func lastBackupEvent() -> VaultBackupEvent?
    /// Logs a PDF backup, once it's been saved somewhere.
    ///
    /// - Parameters:
    ///   - backupDate: When the vault was exported into the backup, which is what the backup's age goes by. The event
    ///     is dated now.
    ///   - vaultToken: The vault the backup was made of: `vaultToken` when it was.
    func exportedToPDF(backupDate: Date, hash: Digest<VaultApplicationPayload>.SHA256, vaultToken: Int)
    /// Logs a transfer to another device. `backupDate` is when the vault was exported for it.
    func exportedToDevice(backupDate: Date, hash: Digest<VaultApplicationPayload>.SHA256, vaultToken: Int)
    /// Logs an auto-backup. `backupDate` is when the vault was exported for it.
    func exportedToAutoBackup(
        backupDate: Date,
        hash: Digest<VaultApplicationPayload>.SHA256,
        providerID: String,
        vaultToken: Int,
    )
    /// Publishes whenever an event is logged.
    var loggedEventPublisher: AnyPublisher<VaultBackupEvent, Never> { get }
}

// MARK: - Impl

/// Logs each event to `storage`: the open vault's own settings, or `UserDefaults` for the plain store.
public final class BackupEventLoggerImpl: BackupEventLogger {
    private let storage: any BackupEventStorage
    private let clock: any EpochClock
    private let loggedEventSubject = PassthroughSubject<VaultBackupEvent, Never>()

    public init(storage: any BackupEventStorage, clock: any EpochClock) {
        self.storage = storage
        self.clock = clock
    }

    /// Keeps the event in `UserDefaults`, device-wide.
    public convenience init(defaults: Defaults, clock: any EpochClock) {
        self.init(storage: defaults, clock: clock)
    }

    public var vaultToken: Int {
        storage.vaultToken
    }

    public func lastBackupEvent() -> VaultBackupEvent? {
        storage.lastBackupEvent()
    }

    public func exportedToPDF(backupDate: Date, hash: Digest<VaultApplicationPayload>.SHA256, vaultToken: Int) {
        log(.exportedToPDF, backupDate: backupDate, hash: hash, vaultToken: vaultToken)
    }

    public func exportedToDevice(backupDate: Date, hash: Digest<VaultApplicationPayload>.SHA256, vaultToken: Int) {
        log(.exportedToDevice, backupDate: backupDate, hash: hash, vaultToken: vaultToken)
    }

    public func exportedToAutoBackup(
        backupDate: Date,
        hash: Digest<VaultApplicationPayload>.SHA256,
        providerID: String,
        vaultToken: Int,
    ) {
        log(.exportedToAutoBackup(providerID: providerID), backupDate: backupDate, hash: hash, vaultToken: vaultToken)
    }

    public var loggedEventPublisher: AnyPublisher<VaultBackupEvent, Never> {
        loggedEventSubject.eraseToAnyPublisher()
    }

    private func log(
        _ kind: VaultBackupEvent.Kind,
        backupDate: Date,
        hash: Digest<VaultApplicationPayload>.SHA256,
        vaultToken: Int,
    ) {
        let event = VaultBackupEvent(
            backupDate: backupDate,
            eventDate: clock.currentDate,
            kind: kind,
            payloadHash: hash,
        )
        do {
            try storage.saveLastBackupEvent(event, for: vaultToken)
            loggedEventSubject.send(event)
        } catch {
            // No event: it couldn't be saved, or the vault it's for isn't open any more.
        }
    }
}
