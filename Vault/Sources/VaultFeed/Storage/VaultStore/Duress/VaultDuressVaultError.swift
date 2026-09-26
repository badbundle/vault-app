import Foundation

/// Why a duress vault wasn't made. Each leaves the vault file as it was.
///
/// None of them depends on what's in any other slot, so trying a password here says nothing about the vaults the
/// open one can't see (MANIFESTO C2).
public enum VaultDuressVaultError: Error, Equatable, Sendable {
    /// The new password is the open vault's own App Lock Password: it must differ from it. That's checked the same way
    /// in every vault.
    case matchesAppLockPassword
    /// The open vault isn't an encrypted one, so there's no slot to make a duress vault in.
    case notEncrypted
    /// The open vault's list of duress slots isn't one the app writes, so it can't say where a duress vault goes.
    case unavailable
}
