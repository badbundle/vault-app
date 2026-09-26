import Foundation

/// Keeps the device's unlock deadline: how long every unlock attempt takes from when it's counted, whether the
/// password is right, a duress password or wrong.
///
/// Calibration sets it when the encrypted vault is created, at 1.5 times the expected key derivation, and it's kept
/// with the storage state (VAULT-47), not in the file's header, because it belongs to the device. It's only ever
/// raised.
public protocol VaultUnlockDeadlineStoring: Sendable {
    func unlockDeadline() async throws -> Duration
    /// Raises the deadline. It's never lowered.
    func raiseUnlockDeadline(to deadline: Duration) async throws
}

/// The time unlocking is measured and held with.
public protocol VaultUnlockClock: Sendable {
    var now: ContinuousClock.Instant { get }
    /// Waits until `deadline`. Throws `CancellationError` if the task is cancelled first.
    func sleep(until deadline: ContinuousClock.Instant) async throws
}

extension ContinuousClock: VaultUnlockClock {
    public func sleep(until deadline: ContinuousClock.Instant) async throws {
        try await sleep(until: deadline, tolerance: nil)
    }
}
