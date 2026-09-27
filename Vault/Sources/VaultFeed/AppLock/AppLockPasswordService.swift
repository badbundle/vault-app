import Foundation

/// The storage side of the App Lock Password, as the lock screen and Settings need it.
///
/// VAULT-46's unlock service unlocks, VAULT-47's conversion sets the password, and VAULT-48 changes it and turns it
/// off: `EncryptedVaultPasswordService` in the app, and `AutofillVaultService` in the AutoFill extension.
/// `FakeAppLockPasswordService` stands in for them in previews and tests.
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

    /// Whether `AppLockPasswordAttemptCounter.eraseThreshold` wrong App Lock Passwords in a row at the lock screen
    /// erase every vault on this device, including any duress vault (VAULT-34). Off unless the user turns it on, and a
    /// setting of the device, not of a vault (`AppLockSettingsStore.erasesAfterFailedPasswords`).
    var erasesAfterFailedPasswords: Bool { get }

    /// How long the user has to wait after wrong passwords before they can try again: zero if they can try now.
    func remainingDelay() async throws -> Duration

    /// Tries the password at the lock screen. If it opens a vault, the app now reads and writes that vault: the real
    /// one or a duress one, which this never says.
    ///
    /// If it's the threshold's wrong password in a row, and erasing after failed passwords is on, it erases every
    /// vault (`VaultEraser`) before it answers, and answers `.erased`: the app now reads and writes a fresh, empty
    /// plain vault. It never answers `.wrong` first (`AppLockPasswordUnlocker`).
    func unlock(password: String) async throws -> AppLockPasswordResult

    /// How many copies of the vault were set aside because they couldn't be opened. They aren't encrypted, so
    /// setting the password deletes them, once the user has agreed (`setPassword(_:deletingSetAsideVaults:)`).
    var setAsideVaultCount: Int { get }

    /// Sets the App Lock Password where there's none, which encrypts the vault with it, or turns it back on after it
    /// was turned off.
    ///
    /// The caller has checked it against `AppLockPasswordRules` and its confirmation.
    ///
    /// - Parameter deletingSetAsideVaults: Whether the user has agreed to delete the copies of the vault set aside
    ///   (`setAsideVaultCount`). If there are any and they haven't, it throws
    ///   `VaultEncryptionError.archivesNeedDeleting` and changes nothing.
    /// - Throws: `VaultEncryptionError` if the vault can't be encrypted as it is, or whatever stopped it. Nothing
    ///   changed then.
    func setPassword(_ password: String, deletingSetAsideVaults: Bool) async throws

    /// Changes the password of the vault that's open, once `current` is shown to be its password.
    func changePassword(current: String, new: String) async throws -> AppLockPasswordResult

    /// Turns the password off for the vault that's open, once `current` is shown to be its password. Erasing after
    /// failed passwords goes off with it.
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

    /// Turns erasing after failed passwords on or off, once `current` is shown to be the password of the vault that's
    /// open (`VaultPasswordChangeService.setErasesAfterFailedPasswords(_:current:)`). A wrong one counts and waits,
    /// as it does for changing the password, but never erases: the vault is open. It's a setting of the device, so any
    /// vault's own password turns it on or off for every vault, a duress vault's included.
    func setErasesAfterFailedPasswords(_ erases: Bool, current: String) async throws -> AppLockPasswordResult

    /// Opens the vault once device authentication has passed, where no password is asked for: when the password is
    /// off after being on, the vault is encrypted with a key on this device, and this opens it. Does nothing while
    /// the vault is plain, or already open.
    func openVaultWithoutPassword() async throws

    /// Locks the vault as the app locks: its keys, and everything read from it, go. The vault then opens again only
    /// as unlocking does. Does nothing while the vault is plain.
    func lockVault() async
}

/// What happened to an attempt at the App Lock Password.
public enum AppLockPasswordResult: Equatable, Sendable {
    /// The password was right, and what it was for is done: a vault opened, or the change was made.
    case accepted
    /// The password was wrong. It counted as a wrong attempt.
    case wrong
    /// The user has to wait this long after their last wrong attempts. Nothing was tried or counted.
    case delayed(Duration)
    /// The password was wrong, the threshold's in a row, and erasing after failed passwords was on: every vault on
    /// this device is erased, and the app now reads and writes a fresh, empty plain vault with no password.
    case erased
    /// Only in the AutoFill extension and Settings: this attempt would make the threshold's in a row, which is only
    /// ever tried at the app's lock screen, so nothing was tried or counted. It says so whether erasing after failed
    /// passwords is on or off, so it doesn't show which.
    case onlyAtTheLockScreen
}
