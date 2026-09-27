import Foundation

/// Stands in for the App Lock Password's storage in previews and tests, until the real one is wired in.
///
/// It keeps its vaults' passwords in memory, and treats wrong passwords as the real one does: each is counted before
/// it's checked, the same delays follow, and every check takes `deadline`, right or wrong. Duress vaults behave as the
/// real ones do: each vault replaces the one it made last, a password opens the most recently made vault it matches,
/// and changing the password only changes the open vault's.
///
/// Erasing after failed passwords behaves as the real one does too (`AppLockPasswordUnlocker`):
/// - the threshold's wrong password in a row at the lock screen "erases": there are no vaults and no password any more;
/// - with that many counted already, the lock screen erases before it tries anything;
/// - Settings never tries the attempt that would make the threshold's;
/// - it's a setting of the device, which any vault's own password turns on or off.
@MainActor
public final class FakeAppLockPasswordService: AppLockPasswordService {
    /// Thrown by every call while it's set, as when the vault can't be read.
    public var failure: (any Error)?

    /// A vault, as far as its password goes.
    private struct Vault {
        /// `nil` once a newer duress vault has replaced it, so no password opens it.
        var password: String?
        /// The duress vault it made last, which the next one it makes replaces.
        var duressVault: Int?
    }

    /// The real vault first, then every duress vault in the order they were made. Empty while no password is set.
    private var vaults: [Vault]
    /// Which of `vaults` is open: the last one a password opened, and the real one at first.
    private var openVault = 0
    public private(set) var erasesAfterFailedPasswords: Bool
    private var attempts: Int
    private var latestAttemptAt: ContinuousClock.Instant
    private let deadline: Duration
    private let clock: any AppLockClock

    /// - Parameters:
    ///   - password: The App Lock Password, or `nil` if none is set.
    ///   - erasesAfterFailedPasswords: Whether erasing after failed passwords is on.
    ///   - wrongAttempts: Wrong attempts in a row already made, just now.
    ///   - deadline: How long every check of a password, and making a duress vault, takes.
    public init(
        password: String? = nil,
        erasesAfterFailedPasswords: Bool = false,
        wrongAttempts: Int = 0,
        deadline: Duration = .zero,
        clock: any AppLockClock = ContinuousClock(),
    ) {
        vaults = password.map { [Vault(password: $0)] } ?? []
        self.erasesAfterFailedPasswords = erasesAfterFailedPasswords
        attempts = wrongAttempts
        latestAttemptAt = clock.now
        self.deadline = deadline
        self.clock = clock
    }

    public var isPasswordSet: Bool {
        !vaults.isEmpty
    }

    public func remainingDelay() async throws -> Duration {
        try failIfNeeded()
        let elapsed = latestAttemptAt.duration(to: clock.now)
        return max(AppLockPasswordAttemptCounter.delay(afterAttempts: attempts) - elapsed, .zero)
    }

    public func unlock(password: String) async throws -> AppLockPasswordResult {
        try failIfNeeded()
        // An erase that's due comes before anything's tried, whatever was entered.
        if erasesAfterFailedPasswords, attempts >= AppLockPasswordAttemptCounter.eraseThreshold {
            erase()
            return .erased
        }
        // The most recently made vault it opens, as the real storage does.
        let result = try await check(opens: vaults.lastIndex { $0.password == password }) { vault in
            openVault = vault
        }
        guard result == .wrong, erasesAfterFailedPasswords, attempts >= AppLockPasswordAttemptCounter.eraseThreshold
        else {
            return result
        }
        erase()
        return .erased
    }

    public func setPassword(_ password: String) async throws {
        try failIfNeeded()
        try await Task.sleep(for: deadline)
        vaults = [Vault(password: password)]
        openVault = 0
        erasesAfterFailedPasswords = false
        attempts = 0
    }

    public func changePassword(current: String, new: String) async throws -> AppLockPasswordResult {
        try await checkInSettings(current) { vault in
            vaults[vault].password = new
        }
    }

    public func turnOffPassword(current: String) async throws -> AppLockPasswordResult {
        try await checkInSettings(current) { _ in
            vaults.removeAll()
            openVault = 0
            erasesAfterFailedPasswords = false
        }
    }

    public func makeDuressVault(password: String) async throws {
        try failIfNeeded()
        try await Task.sleep(for: deadline)
        guard vaults.indices.contains(openVault) else { throw VaultDuressVaultError.notEncrypted }
        guard vaults[openVault].password != password else { throw VaultDuressVaultError.matchesAppLockPassword }
        if let replaced = vaults[openVault].duressVault {
            vaults[replaced].password = nil
        }
        vaults.append(Vault(password: password))
        vaults[openVault].duressVault = vaults.count - 1
    }

    public func setErasesAfterFailedPasswords(_ erases: Bool, current: String) async throws -> AppLockPasswordResult {
        try await checkInSettings(current) { _ in
            erasesAfterFailedPasswords = erases
        }
    }

    /// Every vault goes, and erasing after failed passwords with them.
    private func erase() {
        vaults.removeAll()
        openVault = 0
        erasesAfterFailedPasswords = false
        attempts = 0
    }

    /// Checks `password` is the open vault's, as Settings does: never the attempt that would make the erase
    /// threshold's in a row.
    private func checkInSettings(
        _ password: String,
        accept: (Int) -> Void,
    ) async throws -> AppLockPasswordResult {
        try failIfNeeded()
        guard attempts + 1 < AppLockPasswordAttemptCounter.eraseThreshold else { return .onlyAtTheLockScreen }
        let isOpenVaults = vaults.indices.contains(openVault) && vaults[openVault].password == password
        return try await check(opens: isOpenVaults ? openVault : nil, accept: accept)
    }

    /// Counts the attempt, waits out the deadline, then does `accept` with `vault`: the vault the password opens, if
    /// any.
    private func check(opens vault: Int?, accept: (Int) -> Void) async throws -> AppLockPasswordResult {
        let remaining = try await remainingDelay()
        guard remaining == .zero else { return .delayed(remaining) }
        attempts += 1
        latestAttemptAt = clock.now
        try await Task.sleep(for: deadline)
        guard let vault else { return .wrong }
        attempts = 0
        accept(vault)
        return .accepted
    }

    private func failIfNeeded() throws {
        if let failure {
            throw failure
        }
    }
}
