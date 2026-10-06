import SwiftUI
import VaultFeed

/// Changes the App Lock Password, sets a duress password, or turns erasing after failed passwords on or off: each
/// needs the current password, with the same rules, waits and refusals as on iOS (G18, G27). There's no Turn Off
/// Password on the Mac (G85).
struct VaultMacAppLockPasswordForm: View {
    @State var viewModel: AppLockPasswordFormViewModel
    var close: () -> Void

    var body: some View {
        // Once a second, so a wait counts down.
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let wait = VaultMacPasswordWait.remaining(until: viewModel.retryAt, now: ContinuousClock.now)
            VStack(spacing: 0) {
                form(wait: wait)
                Divider()
                buttons(wait: wait)
            }
        }
        .frame(width: 480)
        .task {
            await viewModel.onAppear()
        }
        .onChange(of: viewModel.state) { _, state in
            if state == .done {
                close()
            }
        }
        .onDisappear {
            viewModel.didDisappear()
        }
    }

    private func form(wait: Duration?) -> some View {
        Form {
            Section {
                Text(Self.explanation(for: viewModel.purpose))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text(Self.title(for: viewModel.purpose))
                    .font(.headline)
            }
            Section {
                if viewModel.needsCurrentPassword {
                    VaultMacSecureField(
                        "Current Password",
                        text: $viewModel.currentPassword,
                        identifier: "settings.password.current",
                    )
                    .disabled(wait != nil || viewModel.isOnlyAtTheLockScreen)
                }
                if viewModel.needsNewPassword {
                    VaultMacSecureField(
                        viewModel.purpose == .setDuress ? "Duress Password" : "New Password",
                        text: $viewModel.newPassword,
                        identifier: "settings.password.new",
                    )
                    VaultMacSecureField(
                        "Confirm Password",
                        text: $viewModel.confirmation,
                        identifier: "settings.password.confirm",
                    )
                }
            } footer: {
                Text(message(wait: wait))
                    .font(.footnote)
                    .foregroundStyle(isProblem(wait: wait) ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .accessibilityIdentifier("settings.password.message")
            }
            .disabled(viewModel.state == .saving)
        }
        .formStyle(.grouped)
        .frame(minHeight: 320)
    }

    private func buttons(wait: Duration?) -> some View {
        HStack {
            if viewModel.state == .saving {
                ProgressView()
                    .controlSize(.small)
            }
            Spacer()
            Button("Cancel", role: .cancel, action: close)
                .keyboardShortcut(.cancelAction)
                .disabled(viewModel.state == .saving)
            Button(Self.action(for: viewModel.purpose)) {
                Task { await viewModel.submit() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!viewModel.canSubmit || wait != nil || viewModel.isOnlyAtTheLockScreen
                || viewModel.state == .saving)
            .accessibilityIdentifier("settings.password.submit")
        }
        .padding()
    }

    private func message(wait: Duration?) -> String {
        if let wait {
            return "Wrong password. " + VaultMacPasswordWait.tryAgainMessage(after: wait)
        }
        if viewModel.isOnlyAtTheLockScreen {
            return "To try the password again, lock Vault and enter it on the lock screen."
        }
        if viewModel.isCurrentPasswordWrong {
            return "That's not the App Lock Password."
        }
        if viewModel.isNewPasswordRefused {
            return "Must be different from your App Lock Password."
        }
        if viewModel.state == .failed {
            return "Vault couldn't do that. Nothing was changed. Try again."
        }
        guard viewModel.needsNewPassword else {
            return "Enter the App Lock Password to confirm."
        }
        if viewModel.isNewPasswordSameAsCurrent {
            return "Choose a password that's different from the current one."
        }
        switch viewModel.newPasswordProblem {
        case .tooShort: return "Use at least \(AppLockPasswordRules.minimumLength) characters."
        case .onlyNumbers: return "Use some letters or symbols, not only numbers."
        case nil: break
        }
        if viewModel.confirmation.isNotEmpty, !viewModel.confirmationMatches {
            return "The passwords don't match."
        }
        return "At least \(AppLockPasswordRules.minimumLength) characters, and not only numbers. A few random words make a strong one."
    }

    private func isProblem(wait: Duration?) -> Bool {
        wait != nil || viewModel.isOnlyAtTheLockScreen || viewModel.isCurrentPasswordWrong
            || viewModel.isNewPasswordRefused || viewModel.state == .failed
            || (viewModel.needsNewPassword && (viewModel.isNewPasswordSameAsCurrent
                    || viewModel.newPasswordProblem != nil
                    || (viewModel.confirmation.isNotEmpty && !viewModel.confirmationMatches)))
    }

    static func title(for purpose: AppLockPasswordFormViewModel.Purpose) -> String {
        switch purpose {
        case .set: "Set an App Lock Password"
        case .change: "Change App Lock Password"
        case .turnOff: "Turn Off App Lock Password"
        case .setDuress: "Set a Duress Password"
        case .turnOnErasing: "Erase After \(AppLockPasswordAttemptCounter.eraseThreshold) Failed Passwords"
        case .turnOffErasing: "Turn Off Erasing"
        }
    }

    static func explanation(for purpose: AppLockPasswordFormViewModel.Purpose) -> String {
        let threshold = AppLockPasswordAttemptCounter.eraseThreshold
        return switch purpose {
        case .set:
            "Vault asks for it every time it unlocks, after Touch ID or your Mac's password. It can't be reset, so if you forget it, the only way back in is to erase Vault and restore a backup."
        case .change:
            "Enter the current password, then choose a new one. It can't be reset, not even with Touch ID or your Mac's password: if you forget it, the only way back in is to erase Vault and restore a backup."
        case .turnOff:
            "Vault will ask only for Touch ID or your Mac's password to unlock."
        case .setDuress:
            "Enter it instead of your App Lock Password when Vault unlocks, and a separate, empty vault opens. Setting it again replaces the last duress vault with a new, empty one."
        case .turnOnErasing:
            "If \(threshold) App Lock Passwords in a row are wrong, Vault erases every vault on this Mac. The right password starts the count again. Only a backup can bring them back."
        case .turnOffErasing:
            "Wrong passwords will only make you wait longer between tries."
        }
    }

    static func action(for purpose: AppLockPasswordFormViewModel.Purpose) -> String {
        switch purpose {
        case .set: "Set Password"
        case .change: "Change Password"
        case .turnOff: "Turn Off"
        case .setDuress: "Set Duress Password"
        case .turnOnErasing: "Turn On Erasing"
        case .turnOffErasing: "Turn Off Erasing"
        }
    }
}
