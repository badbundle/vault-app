import Foundation
import VaultKeygen

/// Storage for the password used to encrypt backups.
///
/// @mockable
public protocol BackupPasswordStore: Observable, Sendable {
    func fetchPassword() async throws -> DerivedEncryptionKey?
    func set(password: DerivedEncryptionKey) async throws
    /// What's known about the stored password, without loading the password itself.
    ///
    /// Unlike `fetchPassword()`, this never asks the user to authenticate (if the store would need
    /// to, it throws instead), so it's safe to call from surfaces that aren't behind device
    /// authentication. Returns `nil` if no password is set.
    func fetchPasswordMetadata() async throws -> BackupPasswordMetadata?
}

/// Non-sensitive facts about the stored backup password.
public struct BackupPasswordMetadata: Equatable, Sendable {
    /// When the password was last set, if the store knows.
    public var lastSetDate: Date?

    public init(lastSetDate: Date?) {
        self.lastSetDate = lastSetDate
    }
}
