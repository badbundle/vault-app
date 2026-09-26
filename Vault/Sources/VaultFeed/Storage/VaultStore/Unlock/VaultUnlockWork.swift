import Foundation

/// The costly steps of an unlock attempt.
///
/// `VaultUnlockService` takes each step the same number of times whatever the password: one derivation, a trial of
/// every slot's key box, and one body opened. Tests count them through this.
protocol VaultUnlockWork: Sendable {
    /// Derives `K_pw` from the password's bytes, with the file's Argon2id parameters and salt.
    func passwordKey(for password: Data, header: VaultSlotFile.Header) throws -> VaultSlotRootKey
    /// Opens slot `index`'s key box with the password's key, or `nil` if it doesn't open.
    func openKeyBox(_ index: Int, in file: VaultSlotFile, with key: VaultSlotRootKey) -> VaultSlotFile.OpenedSlot?
    /// Opens the slot's body and decodes the vault in it.
    func openBody(of slot: VaultSlotFile.OpenedSlot, in file: VaultSlotFile) throws -> VaultRecordState
}

/// The real steps: Argon2id, AES-GCM and the payload's JSON.
struct LiveVaultUnlockWork: VaultUnlockWork {
    func passwordKey(for password: Data, header: VaultSlotFile.Header) throws -> VaultSlotRootKey {
        try header.passwordKey(for: password)
    }

    func openKeyBox(_ index: Int, in file: VaultSlotFile, with key: VaultSlotRootKey) -> VaultSlotFile.OpenedSlot? {
        try? file.openSlot(index, with: key)
    }

    func openBody(of slot: VaultSlotFile.OpenedSlot, in file: VaultSlotFile) throws -> VaultRecordState {
        try EncryptedVaultPayload.decode(slot: slot, in: file)
    }
}
