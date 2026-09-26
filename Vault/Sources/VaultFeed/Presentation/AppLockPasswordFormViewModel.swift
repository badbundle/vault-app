import Foundation
import FoundationExtensions

/// Sets, changes or turns off the App Lock Password, for its screens in Settings.
///
/// Changing it and turning it off need the current password. A wrong one counts as a wrong attempt and waits, just as
/// at the lock screen, and the screen says only that it was wrong and how long to wait: never how many attempts are
/// left.
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
    public var newPassword = ""
    public var confirmation = ""
    public private(set) var state = State.editing
    /// Whether the current password was wrong last time.
    public private(set) var isCurrentPasswordWrong = false
    /// Counts wrong current passwords, so the screen can react to each one.
    public private(set) var wrongPasswordCount = 0
    /// When the current password can be tried again, if the user has to wait after wrong ones. By `AppLockClock`.
    public private(set) var retryAt: ContinuousClock.Instant?

    private let appLock: AppLockService

    public init(purpose: Purpose, appLock: AppLockService) {
        self.purpose = purpose
        self.appLock = appLock
    }

    /// Whether the form asks for the current password.
    public var needsCurrentPassword: Bool {
        purpose != .set
    }

    /// Whether the form asks for a new password, and its confirmation.
    public var needsNewPassword: Bool {
        purpose != .turnOff
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
        guard state != .saving else { return false }
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
            }
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
        case .accepted:
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
