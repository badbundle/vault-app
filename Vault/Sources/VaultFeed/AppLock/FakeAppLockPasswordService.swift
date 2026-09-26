import Foundation

/// Stands in for the App Lock Password's storage in previews and tests, until the real one is wired in.
///
/// It keeps the password in memory, and treats wrong passwords as the real one does: each is counted before it's
/// checked, the same delays follow, and every check takes `deadline`, right or wrong.
@MainActor
public final class FakeAppLockPasswordService: AppLockPasswordService {
    /// Thrown by every call while it's set, as when the vault can't be read.
    public var failure: (any Error)?

    private var password: String?
    private var attempts: Int
    private var latestAttemptAt: ContinuousClock.Instant
    private let deadline: Duration
    private let clock: any AppLockClock

    /// - Parameters:
    ///   - password: The App Lock Password, or `nil` if none is set.
    ///   - wrongAttempts: Wrong attempts in a row already made, just now.
    ///   - deadline: How long every check of a password takes.
    public init(
        password: String? = nil,
        wrongAttempts: Int = 0,
        deadline: Duration = .zero,
        clock: any AppLockClock = ContinuousClock(),
    ) {
        self.password = password
        attempts = wrongAttempts
        latestAttemptAt = clock.now
        self.deadline = deadline
        self.clock = clock
    }

    public var isPasswordSet: Bool {
        password != nil
    }

    public func remainingDelay() async throws -> Duration {
        try failIfNeeded()
        let elapsed = latestAttemptAt.duration(to: clock.now)
        return max(AppLockPasswordAttemptCounter.delay(afterAttempts: attempts) - elapsed, .zero)
    }

    public func unlock(password: String) async throws -> AppLockPasswordResult {
        try await check(password) {}
    }

    public func setPassword(_ password: String) async throws {
        try failIfNeeded()
        try await Task.sleep(for: deadline)
        self.password = password
        attempts = 0
    }

    public func changePassword(current: String, new: String) async throws -> AppLockPasswordResult {
        try await check(current) {
            password = new
        }
    }

    public func turnOffPassword(current: String) async throws -> AppLockPasswordResult {
        try await check(current) {
            password = nil
        }
    }

    /// Counts the attempt, waits out the deadline, then does `accept` if the password is right.
    private func check(_ entered: String, accept: () -> Void) async throws -> AppLockPasswordResult {
        let remaining = try await remainingDelay()
        guard remaining == .zero else { return .delayed(remaining) }
        attempts += 1
        latestAttemptAt = clock.now
        try await Task.sleep(for: deadline)
        guard let password, entered == password else { return .wrong }
        attempts = 0
        accept()
        return .accepted
    }

    private func failIfNeeded() throws {
        if let failure {
            throw failure
        }
    }
}
