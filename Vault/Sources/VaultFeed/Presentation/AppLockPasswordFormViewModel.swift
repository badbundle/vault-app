import Foundation
import FoundationExtensions

/// Sets, changes or turns off the App Lock Password, sets a duress password, or turns erasing after failed passwords
/// on or off, for their screens in Settings.
///
/// Changing it, turning it off, and turning erasing on or off need the current password. A wrong one counts as a wrong
/// attempt and waits, just as at the lock screen, and the screen says only that it was wrong and how long to wait:
/// never how many attempts are left.
///
/// Setting a duress password looks and behaves the same whether or not one was set before, and in a duress vault as in
/// the real one: nothing here knows (MANIFESTO.md C2, C9).
@MainActor
@Observable
public final class AppLockPasswordFormViewModel {
    public enum Purpose: Equatable, Sendable {
        /// Set a password where there's none.
        case set
        /// Change the password, which needs the current one.
        case change
        /// Turn the password off, which needs the current one.
        case turnOff
        /// Set a duress password, which makes a new, empty duress vault that it opens. It replaces the last one.
        case setDuress
        /// Turn on erasing every vault after too many wrong passwords in a row, which needs the current one.
        case turnOnErasing
        /// Turn off erasing after too many wrong passwords, which needs the current one.
        case turnOffErasing
    }

    public enum State: Equatable, Sendable {
        case editing
        case saving
        /// The password is set, changed or off.
        case done
        /// It couldn't be done, and nothing changed.
        case failed
    }

    public let purpose: Purpose
    public var currentPassword = ""
    public var newPassword = "" {
        didSet {
            // What was refused has gone.
            isNewPasswordRefused = false
        }
    }

    public var confirmation = ""
    public private(set) var state = State.editing
    /// Whether the current password was wrong last time.
    public private(set) var isCurrentPasswordWrong = false
    /// Counts wrong current passwords, so the screen can react to each one.
    public private(set) var wrongPasswordCount = 0
    /// Whether the last new password was refused for being the App Lock Password, until another is typed. Only a
    /// duress password is refused this way, by the password service: the form doesn't compare it with anything.
    public private(set) var isNewPasswordRefused = false
    /// Counts refused new passwords, so the screen can react to each one.
    public private(set) var refusedPasswordCount = 0
    /// When the current password can be tried again, if the user has to wait after wrong ones. By `AppLockClock`.
    public private(set) var retryAt: ContinuousClock.Instant?
    /// Whether the current password can only be tried at the lock screen now: the next attempt would make the erase
    /// threshold's wrong one in a row, which Settings never tries, erasing on or off (VAULT-34). The screen says to
    /// lock Vault, and never why.
    public private(set) var isOnlyAtTheLockScreen = false

    private let appLock: AppLockService

    public init(purpose: Purpose, appLock: AppLockService) {
        self.purpose = purpose
        self.appLock = appLock
    }

    /// Whether the form asks for the current password: to change it or turn it off, or to turn erasing on or off.
    public var needsCurrentPassword: Bool {
        switch purpose {
        case .change, .turnOff, .turnOnErasing, .turnOffErasing: true
        case .set, .setDuress: false
        }
    }

    /// Whether the form asks for a new password, and its confirmation.
    public var needsNewPassword: Bool {
        switch purpose {
        case .set, .change, .setDuress: true
        case .turnOff, .turnOnErasing, .turnOffErasing: false
        }
    }

    /// The rule the new password breaks, once something's been typed.
    public var newPasswordProblem: AppLockPasswordRules.Problem? {
        guard needsNewPassword, newPassword.isNotEmpty else { return nil }
        return AppLockPasswordRules.problem(with: newPassword)
    }

    /// Whether the new password is the one it would replace, which wouldn't change anything.
    public var isNewPasswordSameAsCurrent: Bool {
        purpose == .change && newPassword.isNotEmpty && newPassword == currentPassword
    }

    public var confirmationMatches: Bool {
        newPassword == confirmation
    }

    public var canSubmit: Bool {
        guard state != .saving, !isOnlyAtTheLockScreen else { return false }
        if needsCurrentPassword, currentPassword.isEmpty {
            return false
        }
        if needsNewPassword {
            return AppLockPasswordRules.problem(with: newPassword) == nil && !isNewPasswordSameAsCurrent &&
                confirmationMatches
        }
        return true
    }

    /// Finds out whether the current password has to wait before it can be tried.
    public func onAppear() async {
        guard needsCurrentPassword else { return }
        retryAt = await appLock.passwordRetryTime()
    }

    public func submit() async {
        guard canSubmit else { return }
        state = .saving
        isCurrentPasswordWrong = false
        do {
            switch purpose {
            case .set:
                if try await appLock.setPassword(newPassword) {
                    finish()
                } else {
                    // The user didn't authenticate: nothing changed, and they can try again.
                    state = .editing
                }
            case .change:
                try await handle(appLock.changePassword(current: currentPassword, new: newPassword))
            case .turnOff:
                try await handle(appLock.turnOffPassword(current: currentPassword))
            case .setDuress:
                if try await appLock.makeDuressVault(password: newPassword) {
                    finish()
                } else {
                    state = .editing
                }
            case .turnOnErasing:
                try await handle(appLock.setErasesAfterFailedPasswords(true, current: currentPassword))
            case .turnOffErasing:
                try await handle(appLock.setErasesAfterFailedPasswords(false, current: currentPassword))
            }
        } catch VaultDuressVaultError.matchesAppLockPassword {
            clearPasswords()
            isNewPasswordRefused = true
            refusedPasswordCount += 1
            state = .editing
        } catch {
            clearPasswords()
            state = .failed
        }
    }

    /// Forgets what was typed, so no password outlives the screen that collected it.
    public func didDisappear() {
        clearPasswords()
    }

    private func handle(_ result: AppLockPasswordResult) async {
        switch result {
        case .accepted, .erased:
            // Only the lock screen erases, so a screen in Settings never gets `.erased`.
            finish()
        case .wrong:
            // Whether to wait is known before the screen shows the password was wrong, so it shows both at once.
            retryAt = await appLock.passwordRetryTime()
            currentPassword = ""
            isCurrentPasswordWrong = true
            wrongPasswordCount += 1
            state = .editing
        case .delayed:
            retryAt = await appLock.passwordRetryTime()
            currentPassword = ""
            state = .editing
        case .onlyAtTheLockScreen:
            // Nothing to wait for here any more: it's only tried at the lock screen.
            retryAt = nil
            currentPassword = ""
            isOnlyAtTheLockScreen = true
            state = .editing
        }
    }

    private func finish() {
        clearPasswords()
        retryAt = nil
        state = .done
    }

    private func clearPasswords() {
        currentPassword = ""
        newPassword = ""
        confirmation = ""
    }
}
