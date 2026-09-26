import Foundation

/// The costly steps of an unlock attempt.
///
/// `VaultUnlockService` takes each step the same number of times whatever the password: one derivation, a trial of
/// every slot's key box, and one body opened. Tests count and time them through this.
protocol VaultUnlockWork: Sendable {
    /// The CPU time the calling thread has used, which the steps are timed with.
    func threadCPUTime() -> Duration
    /// Derives `K_pw` from the password, with the file's Argon2id parameters and salt.
    func passwordKey(for password: String, header: VaultSlotFile.Header) throws -> VaultSlotRootKey
    /// Opens slot `index`'s key box with the password's key, or `nil` if it doesn't open.
    func openKeyBox(_ index: Int, in file: VaultSlotFile, with key: VaultSlotRootKey) -> VaultSlotFile.OpenedSlot?
    /// Opens the slot's body and decodes the vault in it.
    func openBody(of slot: VaultSlotFile.OpenedSlot, in file: VaultSlotFile) throws -> VaultRecordState
}

/// The real steps: Argon2id, AES-GCM and the payload's JSON.
struct LiveVaultUnlockWork: VaultUnlockWork {
    func threadCPUTime() -> Duration {
        var time = timespec()
        clock_gettime(CLOCK_THREAD_CPUTIME_ID, &time)
        return .seconds(time.tv_sec) + .nanoseconds(time.tv_nsec)
    }

    func passwordKey(for password: String, header: VaultSlotFile.Header) throws -> VaultSlotRootKey {
        try header.passwordKey(for: password)
    }

    func openKeyBox(_ index: Int, in file: VaultSlotFile, with key: VaultSlotRootKey) -> VaultSlotFile.OpenedSlot? {
        try? file.openSlot(index, with: key)
    }

    func openBody(of slot: VaultSlotFile.OpenedSlot, in file: VaultSlotFile) throws -> VaultRecordState {
        try EncryptedVaultPayload.decode(slot: slot, in: file)
    }
}
