import Foundation

/// Why an encrypted vault couldn't be read or saved.
public enum EncryptedVaultStoreError: Error, Equatable, Sendable {
    /// Other apps or extensions saved the vault each time this change was about to, so it gave up and wasn't
    /// saved. The store holds what they saved, so trying again starts from there.
    case conflict
    /// The vault's slot has been rewrapped or replaced since the vault was unlocked, for example by a password
    /// change, so this store can't save to it. The vault has to be unlocked again.
    case slotLost
    /// There's no encrypted vault file.
    case fileMissing
    /// The file didn't read back as it was written, so it wasn't used.
    case verificationFailed
    /// The vault was saved by a newer version of the app. Reading it would drop what that version added the next
    /// time it's saved.
    case unsupportedPayloadVersion(UInt32)
}
