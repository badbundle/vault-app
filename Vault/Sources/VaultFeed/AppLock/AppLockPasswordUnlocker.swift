import Foundation

/// Unlocks at the app's lock screen with the App Lock Password, and erases every vault after too many wrong ones in a
/// row, when the user has turned that on (VAULT-34). The app's `AppLockPasswordService` unlocks through this.
///
/// - **The erase comes before the answer.** When `VaultUnlockService` says a wrong password is the erase threshold's
///   in a row, and erasing is on, this erases (`VaultEraser`, through `erase`) and only then answers, with `.erased`.
///   So the lock screen never shows that password was wrong. If the app stops during the erase, the erase has
///   journaled itself by then, and the next launch finishes it.
/// - **An erase that's due comes first.** If `eraseThreshold` or more attempts in a row are counted already, and
///   erasing is on, it erases before it tries anything, whatever was entered: the real password and a duress one
///   included. The count gets there only through attempts that weren't found right: wrong ones, and ones the app was
///   stopped in the middle of, which stay counted, as a wrong one would. A right attempt that's thrown away, because
///   the app locked meanwhile, still resets the count (`VaultUnlockService`), and Settings and AutoFill never try the
///   attempt that would make ten. So it's a tenth attempt that was counted but never acted on.
/// - **A failed erase is finished by the next attempt.** Once it's journaled, no vault can open
///   (`VaultUnlockError.erasing`), so the next attempt, whatever the password, erases again.
/// - **Before the threshold, a right password never erases,** a duress one included: it opens its vault and resets
///   the count, as `VaultUnlockService` does.
///
/// The AutoFill extension never erases: `AutofillVaultService` leaves that attempt to the app.
///
/// Never log, print or measure anything about an attempt or an erase: when an erase happens shows how many wrong
/// passwords were tried.
@MainActor
public struct AppLockPasswordUnlocker {
    private let unlockService: VaultUnlockService
    private let attemptCounter: AppLockPasswordAttemptCounter
    private let settings: AppLockSettingsStore
    private let erase: @MainActor () async throws -> Void

    /// - Parameters:
    ///   - unlockService: Unlocks the encrypted vault, and counts the attempts.
    ///   - attemptCounter: The counter `unlockService` counts with.
    ///   - settings: Where erasing after failed passwords is turned on or off.
    ///   - erase: Erases every vault, and forgets what the app holds from them: `VaultRoot.eraseVault()`.
    public init(
        unlockService: VaultUnlockService,
        attemptCounter: AppLockPasswordAttemptCounter,
        settings: AppLockSettingsStore,
        erase: @escaping @MainActor () async throws -> Void,
    ) {
        self.unlockService = unlockService
        self.attemptCounter = attemptCounter
        self.settings = settings
        self.erase = erase
    }

    /// Tries the password, and erases every vault first if it's the threshold's wrong one in a row and erasing is on,
    /// or instead of trying it, if an erase is due already.
    ///
    /// - Throws: As `VaultUnlockService.unlock(password:stoppingBeforeEraseThreshold:)` does, or the erase's error, if
    ///   it failed. No vault can open then, and the next attempt finishes the erase.
    public func unlock(password: String) async throws -> AppLockPasswordResult {
        // The count is read every time, erasing on or off, so an attempt takes the same time either way (C2).
        let isEraseDue = try await attemptCounter.hasReachedEraseThreshold()
        if isEraseDue, settings.erasesAfterFailedPasswords {
            try await erase()
            return .erased
        }
        let result: VaultUnlockResult
        do {
            result = try await unlockService.unlock(password: password)
        } catch VaultUnlockError.erasing {
            try await erase()
            return .erased
        }
        switch result {
        case .unlocked:
            return .accepted
        case let .mustWait(remaining):
            return .delayed(remaining)
        case let .wrongPassword(reachesEraseThreshold):
            guard reachesEraseThreshold, settings.erasesAfterFailedPasswords else { return .wrong }
            try await erase()
            return .erased
        }
    }
}
