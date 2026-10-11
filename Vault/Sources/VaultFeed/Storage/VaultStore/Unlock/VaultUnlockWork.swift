import Foundation

/// The costly steps of an unlock attempt.
///
/// `VaultUnlockService` takes each step the same number of times whatever the password: one derivation, a trial of
/// every slot's key box, and one body opened. Tests count and time them through this.
protocol VaultUnlockWork: Sendable {
    /// The CPU time the steps have used, as a running total they're timed with, for a derivation with `lanes` lanes:
    /// the calling thread's, and with more than one lane, a share of the threads the lanes run on.
    func cpuTime(lanes: UInt32) -> Duration
    /// Derives `K_pw` from the password, with the file's Argon2id parameters and salt.
    func passwordKey(for password: String, header: VaultSlotFile.Header) throws -> VaultSlotRootKey
    /// Opens slot `index`'s key box with the password's key, or `nil` if it doesn't open.
    func openKeyBox(_ index: Int, in file: VaultSlotFile, with key: VaultSlotRootKey) -> VaultSlotFile.OpenedSlot?
    /// Opens the slot's body and decodes the vault in it.
    func openBody(of slot: VaultSlotFile.OpenedSlot, in file: VaultSlotFile) throws -> VaultRecordState
}

/// The real steps: Argon2id, AES-GCM and the payload's JSON.
struct LiveVaultUnlockWork: VaultUnlockWork {
    /// With one lane, the calling thread's CPU time: Argon2id runs on it, and starts no thread.
    ///
    /// With more, each lane runs on a thread of its own, side by side, and the calling thread only waits for them. Its
    /// own CPU time then counts in full, and the rest of the process's is divided between the lanes, as that's about
    /// how long they take when they aren't held up. That share includes any other thread of the app's that ran
    /// meanwhile, which is little next to a derivation.
    func cpuTime(lanes: UInt32) -> Duration {
        let thread = Self.cpuTime(of: CLOCK_THREAD_CPUTIME_ID)
        guard lanes > 1 else { return thread }
        let process = Self.cpuTime(of: CLOCK_PROCESS_CPUTIME_ID)
        return thread + (process - thread) / Int(lanes)
    }

    private static func cpuTime(of clock: clockid_t) -> Duration {
        var time = timespec()
        clock_gettime(clock, &time)
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
