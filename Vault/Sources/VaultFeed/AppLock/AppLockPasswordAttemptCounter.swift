import Foundation

/// Counts attempts at the app lock password, and makes the user wait longer and longer between them once they've
/// got it wrong a few times in a row, as iOS does for the device passcode.
///
/// The unlock service counts every attempt with `countAttempt()` **before** it derives the key, and calls `reset()`
/// once the password has opened a vault. Force-quitting the app while the key is being derived can't take back a
/// wrong attempt: it's already counted. Any password that opens a vault resets the count, the real one and a duress
/// one alike, so the count never shows which vault opened (MANIFESTO.md C2). The counter doesn't know about vaults,
/// and behaves the same however many there are.
///
/// **The delay** after each wrong attempt is in `delay(afterAttempts:)`. The count and the time of the latest attempt
/// are kept in the keychain, so relaunching the app, or reinstalling it over the top, doesn't end a delay. The time
/// comes from `AppLockClock`, which counts from when the device started: changing the date and time doesn't move it,
/// either way. It only goes back when the device restarts, and then the delay starts again in full. So a delay can
/// only ever count less time than really passed, never more.
///
/// **What the lock screen shows** is how long the user has to wait (`remainingDelay()`), and nothing else: not how
/// many attempts they've made, or how many are left before the vault is erased (VAULT-34). Counting down to an erase
/// would tell someone forcing the user to guess that it's armed, and when to stop.
///
/// Never log, print or measure anything about the attempts.
public actor AppLockPasswordAttemptCounter {
    /// How many wrong attempts in a row erase the vault, when the user has turned that on (VAULT-34), as with iOS's
    /// Erase Data.
    public static let eraseThreshold = 10

    private let storage: any AppLockPasswordAttemptStorage
    private let clock: any AppLockClock

    /// A counter that keeps its count in the keychain, where the AutoFill extension can count against it too.
    public init(clock: any AppLockClock = ContinuousClock()) {
        self.init(storage: AppLockPasswordAttemptKeychainStorage(), clock: clock)
    }

    init(storage: any AppLockPasswordAttemptStorage, clock: any AppLockClock) {
        self.storage = storage
        self.clock = clock
    }

    /// How long the user has to wait before they can try the password again: zero if they can try it now.
    ///
    /// An attempt that's still underway counts as a wrong one, so ask once it's over.
    public func remainingDelay() throws -> Duration {
        let now = clock.now
        guard let record = try currentRecord(now: now) else { return .zero }
        return Self.remainingDelay(after: record, now: now)
    }

    /// Counts an attempt at the password. Call it before deriving the key, and try the password only if the attempt
    /// was counted.
    ///
    /// - Returns: `.counted` once the attempt is in storage, or `.delayed` if the user still has to wait after their
    ///   last wrong attempt. A delayed attempt isn't counted, and the password mustn't be tried.
    /// - Throws: If the count can't be read or saved. The password mustn't be tried then either.
    public func countAttempt() throws -> AppLockPasswordAttempt {
        let now = clock.now
        let previous = try currentRecord(now: now)
        if let previous {
            let remaining = Self.remainingDelay(after: previous, now: now)
            guard remaining == .zero else { return .delayed(remaining) }
        }
        let count = (previous?.count ?? 0) + 1
        try storage.save(AppLockPasswordAttemptRecord(count: count, latestAt: now))
        return .counted(reachesEraseThreshold: count >= Self.eraseThreshold)
    }

    /// Clears the count once a password has opened a vault, whichever vault it was.
    ///
    /// Clear it too when a password is set where there wasn't one, so that a count left in the keychain from before,
    /// which can outlive even deleting the app, doesn't carry over to the new password.
    public func reset() throws {
        try storage.remove()
    }

    // MARK: - Delay

    /// How long the user has to wait after `attempts` wrong attempts in a row before they can try again.
    ///
    /// These are iOS's delays for the device passcode (Apple Platform Security, "Escalating time delays for passcode
    /// attempts"):
    ///
    /// | Wrong attempts in a row | Delay |
    /// | --- | --- |
    /// | 1 to 4 | None |
    /// | 5 | 1 minute |
    /// | 6 | 5 minutes |
    /// | 7 or 8 | 15 minutes |
    /// | 9 or more | 1 hour |
    ///
    /// On top of that, every attempt takes the time the key derivation is calibrated to, about half a second.
    static func delay(afterAttempts attempts: Int) -> Duration {
        switch attempts {
        case ..<5: .zero
        case 5: .seconds(60)
        case 6: .seconds(5 * 60)
        case 7, 8: .seconds(15 * 60)
        default: .seconds(60 * 60)
        }
    }

    private static func remainingDelay(
        after record: AppLockPasswordAttemptRecord,
        now: ContinuousClock.Instant,
    ) -> Duration {
        let elapsed = record.latestAt.duration(to: now)
        return max(delay(afterAttempts: record.count) - elapsed, .zero)
    }

    /// The stored record, with the delay started again if the clock is now earlier than the latest attempt.
    ///
    /// That only happens when the device has restarted since, and there's no telling how long it was off. So the
    /// delay starts again in full from now, and that's saved, so it doesn't start again on every launch.
    private func currentRecord(now: ContinuousClock.Instant) throws -> AppLockPasswordAttemptRecord? {
        guard var record = try storage.load() else { return nil }
        if now < record.latestAt {
            record.latestAt = now
            try storage.save(record)
        }
        return record
    }
}

/// The result of counting an attempt at the app lock password, before the password is tried.
public enum AppLockPasswordAttempt: Equatable, Sendable {
    /// The attempt is counted: go ahead and try the password.
    ///
    /// - reachesEraseThreshold: Whether this attempt makes `AppLockPasswordAttemptCounter.eraseThreshold` or more in
    ///   a row. If the password turns out wrong, that's when VAULT-34 erases the vault, if the user has turned that
    ///   on. An attempt the app was stopped in the middle of stays counted as wrong, so the attempt after it reaches
    ///   the threshold too.
    case counted(reachesEraseThreshold: Bool)
    /// The user still has to wait this long after their last wrong attempt. The attempt isn't counted, and the
    /// password mustn't be tried.
    case delayed(Duration)
}
