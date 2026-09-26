import Combine
import CryptoEngine
import Foundation
import FoundationExtensions
import VaultCore

/// Logs backup events so the user has visibility when the last one was performed.
///
/// @mockable
@MainActor
public protocol BackupEventLogger: Sendable {
    func lastBackupEvent() -> VaultBackupEvent?
    /// Logs a PDF backup, once it's been saved somewhere.
    ///
    /// - Parameter backupDate: When the vault was exported into the backup, which is what the backup's age goes by.
    ///   The event is dated now.
    func exportedToPDF(backupDate: Date, hash: Digest<VaultApplicationPayload>.SHA256)
    /// Logs a transfer to another device. `backupDate` is when the vault was exported for it.
    func exportedToDevice(backupDate: Date, hash: Digest<VaultApplicationPayload>.SHA256)
    /// Logs an auto-backup. `backupDate` is when the vault was exported for it.
    func exportedToAutoBackup(backupDate: Date, hash: Digest<VaultApplicationPayload>.SHA256, providerID: String)
    /// Publishes whenever an event is logged.
    var loggedEventPublisher: AnyPublisher<VaultBackupEvent, Never> { get }
}

// MARK: - Impl

public final class BackupEventLoggerImpl: BackupEventLogger {
    private let defaults: Defaults
    private let clock: any EpochClock
    private let backupEventKey = Key<VaultBackupEvent>(VaultIdentifiers.Backup.lastBackupEvent)
    private let loggedEventSubject = PassthroughSubject<VaultBackupEvent, Never>()

    public init(defaults: Defaults, clock: any EpochClock) {
        self.defaults = defaults
        self.clock = clock
    }

    public func lastBackupEvent() -> VaultBackupEvent? {
        defaults.get(for: backupEventKey)
    }

    public func exportedToPDF(backupDate: Date, hash: Digest<VaultApplicationPayload>.SHA256) {
        let event = VaultBackupEvent(
            backupDate: backupDate,
            eventDate: clock.currentDate,
            kind: .exportedToPDF,
            payloadHash: hash,
        )
        do {
            try defaults.set(event, for: backupEventKey)
            loggedEventSubject.send(event)
        } catch {
            // no event
        }
    }

    public func exportedToDevice(backupDate: Date, hash: Digest<VaultApplicationPayload>.SHA256) {
        let event = VaultBackupEvent(
            backupDate: backupDate,
            eventDate: clock.currentDate,
            kind: .exportedToDevice,
            payloadHash: hash,
        )
        do {
            try defaults.set(event, for: backupEventKey)
            loggedEventSubject.send(event)
        } catch {
            // no event
        }
    }

    public func exportedToAutoBackup(
        backupDate: Date,
        hash: Digest<VaultApplicationPayload>.SHA256,
        providerID: String,
    ) {
        let event = VaultBackupEvent(
            backupDate: backupDate,
            eventDate: clock.currentDate,
            kind: .exportedToAutoBackup(providerID: providerID),
            payloadHash: hash,
        )
        do {
            try defaults.set(event, for: backupEventKey)
            loggedEventSubject.send(event)
        } catch {
            // no event
        }
    }

    public var loggedEventPublisher: AnyPublisher<VaultBackupEvent, Never> {
        loggedEventSubject.eraseToAnyPublisher()
    }
}
