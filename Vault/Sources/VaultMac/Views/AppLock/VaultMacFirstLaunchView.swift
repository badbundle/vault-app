import SwiftUI
import VaultAppIcon
import VaultFeed

/// The Mac app's first launch: the App Lock Password is set before anything else, and can't be skipped
/// (docs/mac-app.md,
/// decision 1). The same rules as on iOS (G27), and the same warning that it can't be reset (G30). Setting it asks for
/// Touch ID or the Mac's password first, which shows the user can unlock Vault before they need to.
///
/// It's shown again after an erase, which leaves no password.
struct VaultMacFirstLaunchView: View {
    @State private var viewModel: AppLockPasswordFormViewModel
    var canAuthenticate: Bool
    @FocusState private var focusedField: Field?

    private enum Field {
        case password
        case confirmation
    }

    init(appLock: AppLockService, canAuthenticate: Bool) {
        _viewModel = State(initialValue: AppLockPasswordFormViewModel(purpose: .set, appLock: appLock))
        self.canAuthenticate = canAuthenticate
    }

    var body: some View {
        VStack(spacing: 24) {
            VaultMacAppIconView()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("Set an App Lock Password")
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(
                    "Vault on the Mac is always encrypted with a password of its own. You'll enter it after Touch ID or your Mac's password each time you unlock Vault.",
                )
                .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 420)

            VStack(alignment: .leading, spacing: 10) {
                SecureField("Password", text: $viewModel.newPassword)
                    .secretTextInput()
                    .focused($focusedField, equals: .password)
                    .onSubmit { focusedField = .confirmation }
                    .accessibilityIdentifier("first-launch.password")
                SecureField("Confirm Password", text: $viewModel.confirmation)
                    .secretTextInput()
                    .focused($focusedField, equals: .confirmation)
                    .onSubmit(submit)
                    .accessibilityIdentifier("first-launch.confirmation")
                Text(hint)
                    .font(.callout)
                    .foregroundStyle(isShowingProblem ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .accessibilityIdentifier("first-launch.hint")
            }
            .textFieldStyle(.roundedBorder)
            .controlSize(.large)
            .disabled(viewModel.state == .saving)
            .frame(width: 320)

            Label {
                Text(
                    "There's no way to reset this password. If you forget it, the only way back into Vault is to erase it and restore a backup.",
                )
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            .font(.callout)
            .frame(maxWidth: 420)

            Button(action: submit) {
                if viewModel.state == .saving {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 160)
                } else {
                    Text("Set Password")
                        .frame(width: 160)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!viewModel.canSubmit || !canAuthenticate)
            .accessibilityIdentifier("first-launch.set-password")
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await viewModel.onAppear()
            focusedField = .password
        }
        .onDisappear {
            viewModel.didDisappear()
        }
    }

    private func submit() {
        guard viewModel.canSubmit, canAuthenticate else { return }
        Task { await viewModel.submit() }
    }

    private var hint: String {
        if !canAuthenticate {
            return "Set a login password for this Mac first: Vault asks for it, or Touch ID, before the App Lock Password."
        }
        if viewModel.state == .failed {
            return "Vault couldn't set the password. Try again."
        }
        switch viewModel.newPasswordProblem {
        case .tooShort:
            return "Use at least 8 characters."
        case .onlyNumbers:
            return "Use letters or symbols too, not only numbers."
        case nil:
            break
        }
        if viewModel.confirmation.isNotEmpty, !viewModel.confirmationMatches {
            return "The passwords don't match."
        }
        return "At least 8 characters, and not only numbers. A few random words make a strong one."
    }

    private var isShowingProblem: Bool {
        !canAuthenticate || viewModel.state == .failed || viewModel.newPasswordProblem != nil
            || (viewModel.confirmation.isNotEmpty && !viewModel.confirmationMatches)
    }
}
