import SwiftUI
import VaultFeed

/// The backup password: whether it's set, and setting or changing it, with the App Lock Password's rules (G27). Each
/// vault has its own (G17).
struct VaultMacBackupPasswordPage: View {
    var services: VaultMacBackupServices
    @Binding var isShowingPasswordSheet: Bool

    var body: some View {
        Form {
            Section {
                LabeledContent("Backup Password") {
                    Text(statusText)
                        .accessibilityIdentifier("backups.password.status")
                }
                Button(services.dataModel.backupPasswordStatus.isSet
                    ? "Change Backup Password…"
                    : "Set Up Backup Password…")
                {
                    isShowingPasswordSheet = true
                }
                .accessibilityIdentifier("backups.password.change")
            } footer: {
                Text(
                    "Backups are encrypted with this password, and you'll need it to restore them. It can't be recovered if you forget it.",
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            await services.dataModel.loadBackupPasswordStatus()
        }
    }

    private var statusText: String {
        switch services.dataModel.backupPasswordStatus {
        case .unknown: "…"
        case .notSet: "Not Set"
        case let .set(metadata):
            if let date = metadata.lastSetDate {
                "Set \(date.formatted(date: .abbreviated, time: .shortened))"
            } else {
                "Set"
            }
        }
    }
}

/// Sets or changes the backup password, after Touch ID or the Mac's password. Deriving its key can take a few
/// minutes, and closing the sheet cancels it.
struct VaultMacBackupPasswordSheet: View {
    @State var viewModel: BackupKeyChangeViewModel
    var close: () -> Void

    @State private var keyGeneration: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                if viewModel.newPassword.isLoading {
                    ProgressView()
                        .controlSize(.small)
                    Text("Securing your password. This can take up to 3 minutes.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if viewModel.newPassword == .success {
                    Button("Done", action: close)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel", role: .cancel) {
                        keyGeneration?.cancel()
                        close()
                    }
                    .keyboardShortcut(.cancelAction)
                    if viewModel.permissionState == .allowed {
                        Button(viewModel.currentPasswordStatus.isSet ? "Change Password" : "Set Password") {
                            save()
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!viewModel.canSetBackupPassword || viewModel.newPassword.isLoading)
                        .accessibilityIdentifier("backups.password.save")
                    }
                }
            }
            .padding()
        }
        .frame(width: 480, height: 360)
        .task {
            await viewModel.onAppear()
        }
        .onDisappear {
            keyGeneration?.cancel()
            viewModel.didDisappear()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.permissionState {
        case .allowed:
            if viewModel.newPassword == .success {
                VaultMacBackupNotice(
                    systemImage: "checkmark.shield.fill",
                    title: viewModel.didReplaceExistingPassword ? "Backup Password Changed" : "Backup Password Set",
                    message: viewModel.didReplaceExistingPassword
                        ? "Your backups will be encrypted with it from now on. Backups made before now still need the password they were made with."
                        :
                        "Your backups will be encrypted with it from now on. Keep it somewhere safe: it can't be recovered if you forget it.",
                )
            } else {
                form
            }
        case .undetermined:
            ProgressView()
        case .denied:
            VaultMacBackupNotice(
                systemImage: "key.horizontal",
                title: "Authenticate",
                message: "Use Touch ID or your Mac's password to set the backup password.",
                action: ("Authenticate", { Task { await viewModel.onAppear() } }),
            )
        case .unavailable:
            VaultMacBackupNotice(
                systemImage: "lock.slash",
                title: "Set Up a Mac Password",
                message: "Setting a backup password needs Touch ID or your Mac's login password.",
            )
        }
    }

    private var form: some View {
        Form {
            Section {
                VaultMacSecureField(
                    "New Password",
                    text: $viewModel.newlyEnteredPassword,
                    identifier: "backups.password.new",
                )
                VaultMacSecureField(
                    "Confirm Password",
                    text: $viewModel.newlyEnteredPasswordConfirm,
                    identifier: "backups.password.confirm",
                )
            } footer: {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(isShowingProblem ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .accessibilityIdentifier("backups.password.hint")
            }
            .disabled(viewModel.newPassword.isLoading)
        }
        .formStyle(.grouped)
    }

    private var isShowingProblem: Bool {
        switch viewModel.newPassword {
        case .keygenError, .keygenCancelled, .passwordConfirmError: true
        case .initial, .creating, .success:
            viewModel.newlyEnteredPasswordConfirm.isNotEmpty && !viewModel.passwordConfirmMatches
        }
    }

    private var problem: String {
        switch viewModel.newPassword {
        case .keygenError: return "Something went wrong. Your backup password was not changed."
        case .keygenCancelled: return "Cancelled. Your backup password was not changed."
        case .passwordConfirmError: return "The passwords don't match."
        case .initial, .creating, .success: break
        }
        if viewModel.newlyEnteredPasswordConfirm.isNotEmpty, !viewModel.passwordConfirmMatches {
            return "The passwords don't match."
        }
        switch viewModel.newPasswordProblem {
        case .tooShort: return "Use at least \(AppLockPasswordRules.minimumLength) characters."
        case .onlyNumbers: return "Use some letters or symbols, not only numbers."
        case nil: return "Use the same rules as the App Lock Password. You'll need it to restore a backup."
        }
    }

    private func save() {
        guard viewModel.canSetBackupPassword else { return }
        keyGeneration?.cancel()
        keyGeneration = Task {
            await viewModel.saveEnteredPassword()
        }
    }
}
