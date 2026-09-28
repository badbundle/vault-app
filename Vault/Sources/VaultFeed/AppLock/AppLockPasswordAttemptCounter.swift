import Foundation

/// Counts attempts at the app lock password, and makes the user wait longer and longer between them once they've
/// got it wrong a few times, as iOS does for the device passcode.
///
/// The unlock service counts every attempt with `countAttempt()` **before** it derives the key, and calls
/// `noteRightAttempt()` once the password has opened a vault. Force-quitting the app while the key is being derived
/// can't take back a wrong attempt: it's already counted. The counter doesn't know about vaults, and behaves the same
/// however many there are: the real password and a duress one do exactly the same to it, so it never shows which vault
/// opened (MANIFESTO.md C2).
///
/// It keeps two counts:
///
/// - **In a row:** attempts since one last opened a vault. Any password that opens a vault starts it again. It decides
///   when to erase (VAULT-34), and where Settings and AutoFill stop.
/// - **Recent:** wrong attempts, whichever vaults opened in between. An attempt that opens a vault takes only itself
///   back off, and the count goes down by one for every hour that passes. So opening a vault between wrong attempts
///   doesn't shorten the delays.
///
/// **The delay** after a wrong attempt is `delay(afterAttempts:)` for whichever count is larger. After an attempt that
/// opened a vault there's none, so the next attempt can be made at once. The counts, the time of the latest attempt
/// and where the recent count's next hour runs from are kept in the keychain, so relaunching the app, or reinstalling
/// it over the top, doesn't end a delay. The time comes from `AppLockClock`, which counts from when the device started:
/// changing the date and time doesn't move it, either way. It only goes back when the device restarts, and then the
/// delay starts again in full, and the recent count goes down only from then. So the counter can only ever count less
/// time than really passed, never more.
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
    /// How long it takes the recent count of wrong attempts to go down by one.
    static let recentWrongInterval = Duration.seconds(60 * 60)

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
    public func remainingDelay() async throws -> Duration {
        let access = try await storage.acquireExclusiveAccess()
        defer { access.release() }
        let now = clock.now
        guard let record = try currentRecord(now: now) else { return .zero }
        return Self.remainingDelay(after: record, now: now)
    }

    /// Counts an attempt at the password. Call it before deriving the key, and try the password only if the attempt
    /// was counted.
    ///
    /// - Parameter stoppingBeforeEraseThreshold: Whether to leave an attempt that would make `eraseThreshold` or more
    ///   in a row uncounted. The AutoFill extension does, and sends the user to the app, where a wrong one can erase
    ///   (VAULT-34). It's decided with the count held against every process, so an attempt the app counts at the same
    ///   moment can't slip in between.
    /// - Returns: `.counted` once the attempt is in storage, `.stoppedBeforeEraseThreshold` if it was asked to stop
    ///   there, or `.delayed` if the user still has to wait after their last wrong attempt. An attempt that isn't
    ///   counted mustn't be tried.
    /// - Throws: If the count can't be read or saved. The password mustn't be tried then either.
    public func countAttempt(stoppingBeforeEraseThreshold: Bool = false) async throws -> AppLockPasswordAttempt {
        let access = try await storage.acquireExclusiveAccess()
        defer { access.release() }
        let now = clock.now
        let previous = try currentRecord(now: now)
        let count = (previous?.count ?? 0) + 1
        if stoppingBeforeEraseThreshold, count >= Self.eraseThreshold {
            return .stoppedBeforeEraseThreshold
        }
        if let previous {
            let remaining = Self.remainingDelay(after: previous, now: now)
            guard remaining == .zero else { return .delayed(remaining) }
        }
        let recent = previous.map { Self.recentWrong(in: $0, now: now) } ?? (count: 0, since: now)
        try storage.save(AppLockPasswordAttemptRecord(
            count: count,
            latestAt: now,
            recentWrong: recent.count + 1,
            recentWrongAt: recent.since,
        ))
        return .counted(reachesEraseThreshold: count >= Self.eraseThreshold)
    }

    /// Whether `eraseThreshold` or more wrong attempts in a row are counted already. Counts nothing.
    ///
    /// With erasing on, that's an erase that's due: the app asks before it tries any password
    /// (`AppLockPasswordUnlocker`), and erases instead, so a tenth wrong attempt that was counted but never acted on,
    /// because the app stopped first, still erases, whatever's entered next. Only wrong attempts get the count there.
    public func hasReachedEraseThreshold() async throws -> Bool {
        let access = try await storage.acquireExclusiveAccess()
        defer { access.release() }
        return try (currentRecord(now: clock.now)?.count ?? 0) >= Self.eraseThreshold
    }

    /// Once a password has opened a vault, whichever vault it was: clears the count in a row, and takes that attempt
    /// back off the recent count. The recent count's other wrong attempts stay, so the next wrong attempt waits as long
    /// as it would have without this one, but the next attempt needn't wait at all.
    public func noteRightAttempt() async throws {
        let access = try await storage.acquireExclusiveAccess()
        defer { access.release() }
        guard var record = try storage.load() else { return }
        record.count = 0
        record.recentWrong = max(record.recentWrong - 1, 0)
        try storage.save(record)
    }

    /// Clears the count in a row only, and leaves the recent count and its delays: for the password turned back on
    /// after it was off, which device authentication alone does.
    public func resetCountInARow() async throws {
        let access = try await storage.acquireExclusiveAccess()
        defer { access.release() }
        guard var record = try storage.load() else { return }
        record.count = 0
        try storage.save(record)
    }

    /// Forgets every attempt: both counts, and any delay. Only for a password set where there wasn't one, so that
    /// attempts left in the keychain from before, which can outlive even deleting the app, don't carry over to it, and
    /// for the erase, which deletes the record with everything else.
    public func reset() async throws {
        let access = try await storage.acquireExclusiveAccess()
        defer { access.release() }
        try storage.remove()
    }

    /// Removes the file the count's lock is taken on, which shows a password was tried on this device. Only an erase
    /// calls it, after `reset()`, once there's no password left to count attempts at: nothing takes the lock again
    /// until a password is set, which makes the file again.
    func removeLockFile() throws {
        try storage.removeLockFile()
    }

    // MARK: - Delay

    /// How long the user has to wait after `attempts` wrong attempts before they can try again: the count in a row or
    /// the recent count, whichever is larger.
    ///
    /// These are iOS's delays for the device passcode (Apple Platform Security, "Escalating time delays for passcode
    /// attempts"):
    ///
    /// | Wrong attempts | Delay |
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

    /// The delay left after the latest attempt: none if it opened a vault, which leaves none in a row.
    private static func remainingDelay(
        after record: AppLockPasswordAttemptRecord,
        now: ContinuousClock.Instant,
    ) -> Duration {
        guard record.count > .zero else { return .zero }
        let elapsed = record.latestAt.duration(to: now)
        return max(delay(afterAttempts: max(record.count, record.recentWrong)) - elapsed, .zero)
    }

    /// The recent count of wrong attempts now, down by one for every whole hour since `recentWrongAt`, and where its
    /// next hour runs from. What's left of an hour carries over, so an attempt that opens a vault, which takes itself
    /// back off, leaves the count exactly as it would have been without it.
    private static func recentWrong(
        in record: AppLockPasswordAttemptRecord,
        now: ContinuousClock.Instant,
    ) -> (count: Int, since: ContinuousClock.Instant) {
        let hours = Int(record.recentWrongAt.duration(to: now) / recentWrongInterval)
        guard hours < record.recentWrong else { return (0, now) }
        return (record.recentWrong - hours, record.recentWrongAt.advanced(by: recentWrongInterval * hours))
    }

    /// The stored record, with the delay started again if the clock is now earlier than the latest attempt.
    ///
    /// That only happens when the device has restarted since, and there's no telling how long it was off. So the
    /// delay starts again in full from now, and the recent count goes down only from now too. That's saved, so it
    /// doesn't start again on every launch.
    private func currentRecord(now: ContinuousClock.Instant) throws -> AppLockPasswordAttemptRecord? {
        guard var record = try storage.load() else { return nil }
        if now < max(record.latestAt, record.recentWrongAt) {
            record.latestAt = min(record.latestAt, now)
            record.recentWrongAt = now
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
    /// Only when asked to stop there: this attempt would make `AppLockPasswordAttemptCounter.eraseThreshold` or more
    /// in a row. It isn't counted, and the password mustn't be tried.
    case stoppedBeforeEraseThreshold
}
