import Foundation

/// The storage side of the App Lock Password, as the lock screen and Settings need it.
///
/// VAULT-46's unlock service unlocks, VAULT-47's conversion sets the password, and VAULT-48 changes it and turns it
/// off. Until those are wired in, `FakeAppLockPasswordService` stands in for them in previews and tests, and the app
/// offers no password at all.
///
/// Everything that takes a password the user already chose counts an attempt with `AppLockPasswordAttemptCounter`
/// before deriving anything, and resets the count if the password is right, so wrong passwords typed into Settings
/// count and wait just as they do on the lock screen. Each of those calls finishes at the device's fixed unlock
/// deadline, whether the password is the real one, a duress one or wrong (MANIFESTO.md C2), and the caller shows the
/// result as soon as it arrives. Nothing may log, print or measure anything about a password or its result.
@MainActor
public protocol AppLockPasswordService {
    /// Whether the App Lock Password is set, so unlocking asks for it after device authentication. Known at launch,
    /// before any vault is open.
    var isPasswordSet: Bool { get }

    /// How long the user has to wait after wrong passwords before they can try again: zero if they can try now.
    func remainingDelay() async throws -> Duration

    /// Tries the password at the lock screen. If it opens a vault, the app now reads and writes that vault: the real
    /// one or a duress one, which this never says.
    func unlock(password: String) async throws -> AppLockPasswordResult

    /// Sets the App Lock Password where there's none, which encrypts the vault with it.
    ///
    /// The caller has checked it against `AppLockPasswordRules` and its confirmation.
    func setPassword(_ password: String) async throws

    /// Changes the password of the vault that's open, once `current` is shown to be its password.
    func changePassword(current: String, new: String) async throws -> AppLockPasswordResult

    /// Turns the password off for the vault that's open, once `current` is shown to be its password.
    func turnOffPassword(current: String) async throws -> AppLockPasswordResult

    /// Makes a duress vault from the vault that's open: a separate, empty vault that `password` opens at the lock
    /// screen. Making one again from the same vault replaces the last one with a new, empty vault.
    ///
    /// It works the same way from the real vault and from a duress vault, whether or not one was made before, and
    /// nothing records that it was made (MANIFESTO.md C2, C6). It isn't an attempt at the App Lock Password, so it
    /// isn't counted and doesn't wait. The caller has checked `password` against `AppLockPasswordRules` and its
    /// confirmation, and nothing else.
    ///
    /// - Throws: `VaultDuressVaultError.matchesAppLockPassword` if `password` is the open vault's own App Lock
    ///   Password. That's the only password it refuses: one that happens to open another vault is accepted without a
    ///   word, or trying passwords here would say which other vaults exist.
    func makeDuressVault(password: String) async throws
}

/// What happened to an attempt at the App Lock Password.
public enum AppLockPasswordResult: Equatable, Sendable {
    /// The password was right, and what it was for is done: a vault opened, or the change was made.
    case accepted
    /// The password was wrong. It counted as a wrong attempt.
    case wrong
    /// The user has to wait this long after their last wrong attempts. Nothing was tried or counted.
    case delayed(Duration)
}
