import Foundation
import FoundationExtensions
import VaultKeygen

/// Carries a stored backup key on to a stronger derivation.
///
/// @mockable
public protocol BackupPasswordUpgrading: Sendable {
    /// `password` carried on to the derivation that replaces its own, or `nil` if Vault has none stronger for it.
    ///
    /// Runs off the main actor, at utility priority, for as long as that derivation takes: seconds on an iPhone.
    func upgraded(_ password: DerivedEncryptionKey) async throws -> DerivedEncryptionKey?
}

/// Moves a stored backup key to a stronger derivation without its password, which Vault never stores (VAULT-128).
///
/// A key derived with `Backup.Secure.v1` becomes `Backup.Secure.v1ThenV2`'s: v2's Argon2id over the stored key, with
/// the same salt (`VaultKeyDeriver.Signature.storedBackupKeyUpgrade`). Backups made with it restore from the password
/// with v1, then v2, and backups made with the old key still restore as they always have.
///
/// The stronger derivation needs 512 MiB, so only the app does this, never an extension: `VaultDataModel` is only
/// given one in the app.
public struct BackupPasswordUpgrader: BackupPasswordUpgrading {
    private let keyDeriverFactory: any VaultKeyDeriverFactory

    public init(keyDeriverFactory: any VaultKeyDeriverFactory) {
        self.keyDeriverFactory = keyDeriverFactory
    }

    public func upgraded(_ password: DerivedEncryptionKey) async throws -> DerivedEncryptionKey? {
        guard let signature = password.keyDervier.storedBackupKeyUpgrade else { return nil }
        let keyDeriver = keyDeriverFactory.lookupVaultKeyDeriver(signature: signature)
        // Nobody waits for it, but at background priority an iPhone could keep it to its efficiency cores for
        // minutes, with its 512 MiB held all the while.
        return try await Task.runDetached(priority: .utility) {
            try keyDeriver.continueDerivation(from: password)
        }
    }
}
