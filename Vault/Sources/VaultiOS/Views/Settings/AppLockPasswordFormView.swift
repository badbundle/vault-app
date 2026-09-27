import Foundation
import SwiftUI
import VaultFeed

/// Sets, changes or turns off the App Lock Password, or sets a duress password.
///
/// Setting it says plainly what forgetting it means, and when the vault was last backed up. Changing it and turning it
/// off ask for the current password, which waits after wrong ones just as the lock screen does, and never says how
/// many attempts are left.
///
/// Setting a duress password shows the same screens every time, in every vault, whether or not one was set before: it
/// never says "create" or "replace", and nothing on it depends on what exists (MANIFESTO.md C2, C9).
struct AppLockPasswordFormView: View {
    @State private var viewModel: AppLockPasswordFormViewModel
    /// For setting it: the vault's last backup, the way back if the password is forgotten.
    private var lastBackup: VaultBackupEvent?
    /// Closes the whole sheet, back to Settings.
    private var close: () -> Void

    @FocusState private var focusedField: Field?

    private enum Field {
        case current, new, confirmation
    }

    init(viewModel: AppLockPasswordFormViewModel, lastBackup: VaultBackupEvent? = nil, close: @escaping () -> Void) {
        _viewModel = State(wrappedValue: viewModel)
        self.lastBackup = lastBackup
        self.close = close
    }

    var body: some View {
        // Ticks while the current password has to wait, so the wait counts down and ends on time.
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            form(passwordWait: AppLockPasswordWait.remaining(until: viewModel.retryAt))
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .interactiveDismissDisabled(viewModel.state == .saving)
        .sensoryFeedback(.success, trigger: viewModel.state) { _, state in
            state == .done
        }
        .navigationBarBackButtonHidden(viewModel.state == .done)
        .task {
            await viewModel.onAppear()
            // Setting a password waits for the user to read what forgetting it means first.
            if viewModel.needsCurrentPassword, viewModel.retryAt == nil {
                focusedField = .current
            }
        }
        .onChange(of: viewModel.wrongPasswordCount) {
            AccessibilityNotification.Announcement("Wrong password.").post()
            if viewModel.retryAt == nil {
                focusedField = .current
            }
        }
        .onChange(of: viewModel.refusedPasswordCount) {
            AccessibilityNotification.Announcement(Self.refusedPasswordMessage).post()
        }
        .onDisappear {
            viewModel.didDisappear()
        }
    }

    private func form(passwordWait: Duration?) -> some View {
        Form {
            if viewModel.state == .done {
                doneSections
            } else {
                headerSection
                if viewModel.purpose == .set {
                    forgettingSection
                    systemSurfacesSection
                }
                if viewModel.purpose == .setDuress {
                    duressSection
                }
                if viewModel.purpose == .turnOff {
                    restoringSection
                }
                if viewModel.needsCurrentPassword {
                    currentPasswordSection(passwordWait: passwordWait)
                }
                if viewModel.needsNewPassword {
                    newPasswordSection
                }
                actionSection(passwordWait: passwordWait)
            }
        }
        .animation(.snappy, value: viewModel.state == .done)
        .animation(.snappy, value: viewModel.isCurrentPasswordWrong)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if viewModel.state == .done {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: close)
            }
        } else if viewModel.purpose == .set {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: close)
                    .tint(.red)
                    .disabled(viewModel.state == .saving)
            }
        }
    }

    private var navigationTitle: String {
        switch viewModel.purpose {
        case .set: "App Lock Password"
        case .change: "Change Password"
        case .turnOff: "Turn Off Password"
        case .setDuress: "Duress Password"
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        Section {
            switch viewModel.purpose {
            case .set:
                BackupHeroHeader(
                    title: "Set an App Lock Password",
                    subtitle: "Vault will ask for it every time it unlocks, after Face ID, Touch ID or your passcode. It's a different password from your backup password.",
                    systemImage: "ellipsis.rectangle.fill",
                    color: .accentColor,
                    iconSize: 56,
                )
            case .change:
                BackupHeroHeader(
                    title: "Change App Lock Password",
                    subtitle: "Enter the current password, then choose a new one.",
                    systemImage: "key.fill",
                    color: .accentColor,
                    iconSize: 56,
                )
            case .turnOff:
                BackupHeroHeader(
                    title: "Turn Off App Lock Password",
                    subtitle: "Vault will ask only for Face ID, Touch ID or your passcode to unlock.",
                    systemImage: "lock.open.fill",
                    color: .red,
                    iconSize: 56,
                )
            case .setDuress:
                BackupHeroHeader(
                    title: "Set a Duress Password",
                    subtitle: "Enter it instead of your App Lock Password when Vault unlocks, and a separate, empty vault opens.",
                    systemImage: Self.duressSystemImage,
                    color: .accentColor,
                    iconSize: 56,
                )
            }
        }
    }

    /// The symbol for the duress password, here and on the row that opens it.
    static let duressSystemImage = "lock.rectangle.stack.fill"

    /// There's no way to reset a forgotten password, so this says so before it's set, with the way back.
    private var forgettingSection: some View {
        Section {
            note(
                title: "If you forget it",
                detail: "It can't be reset, not even with Face ID, Touch ID or your passcode. The only way back in is to erase the vault and restore a backup.",
                systemImage: "exclamationmark.triangle.fill",
                color: .orange,
            )
            if let lastBackup {
                note(
                    title: "Last backup \(lastBackup.backupDate.formatted(date: .abbreviated, time: .shortened))",
                    detail: "If you've changed anything since, make a new backup first.",
                    systemImage: "externaldrive.fill.badge.timemachine",
                    color: .secondary,
                )
            } else {
                note(
                    title: "No backup on this device",
                    detail: "Make a backup first, so you can get your vault back if you forget the password.",
                    systemImage: "externaldrive.fill.badge.exclamationmark",
                    color: .red,
                )
            }
        }
    }

    /// How the duress vault is filled and replaced. The same words every time, whatever exists already.
    private var duressSection: some View {
        Section {
            note(
                title: "Adding items to it",
                detail: "Unlock with the duress password, then add them there.",
                systemImage: "tray.and.arrow.down.fill",
                color: .secondary,
            )
            note(
                title: "Setting it again",
                detail: "Replaces the last duress vault with a new, empty one.",
                systemImage: "arrow.triangle.2.circlepath",
                color: .secondary,
            )
        }
    }

    /// With the password off, a key in this device's keychain opens the vault, and a backup restored onto another
    /// iPhone only brings it if the backup is encrypted, so this says so before it's turned off.
    private var restoringSection: some View {
        Section {
            note(
                title: "Restoring onto another iPhone",
                detail: "With the password off, a key on this device opens the vault. A backup restored onto another iPhone only brings that key if the backup is encrypted, or from iCloud, so keep a backup PDF too.",
                systemImage: "exclamationmark.triangle.fill",
                color: .orange,
            )
        }
    }

    /// While the password is on, the widgets, QuickType and AutoFill show nothing of the vault without it. A widget
    /// that's already been added keeps what it was set up with in the system's widget settings, which Vault can't
    /// clear, so this asks the user to remove it.
    private var systemSurfacesSection: some View {
        Section {
            note(
                title: "Remove your Vault widgets",
                detail: "While the password is on, widgets show Vault as locked. Any you've added still keep their code's name and account in this iPhone's widget settings.",
                systemImage: "square.grid.2x2.fill",
                color: .secondary,
            )
            note(
                title: "AutoFill asks for it too",
                detail: "QuickType stops suggesting codes, and AutoFill asks for the password before it shows any.",
                systemImage: "keyboard.fill",
                color: .secondary,
            )
        }
    }

    private func note(title: String, detail: String, systemImage: String, color: Color) -> some View {
        FormRow(
            image: Image(systemName: systemImage),
            color: color,
            style: .standard,
            alignment: .firstTextBaseline,
        ) {
            TextAndSubtitle(title: title, subtitle: detail)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Passwords

    private func currentPasswordSection(passwordWait: Duration?) -> some View {
        Section {
            LabeledTextField(
                "Current Password",
                text: $viewModel.currentPassword,
                kind: .secure(),
                status: viewModel.isCurrentPasswordWrong ? .error(message: "Wrong password.") : .none,
            )
            .secretTextInput(.verbatim)
            .focused($focusedField, equals: .current)
            .submitLabel(viewModel.needsNewPassword ? .next : .done)
            .onSubmit {
                if viewModel.needsNewPassword {
                    focusedField = .new
                } else {
                    submit()
                }
            }
            .disabled(passwordWait != nil || viewModel.state == .saving)
            .wrongPasswordFeedback(trigger: viewModel.wrongPasswordCount)
        } footer: {
            if let passwordWait {
                Text(AppLockPasswordWait.tryAgainMessage(after: passwordWait))
                    .foregroundStyle(.red)
            }
        }
    }

    private var newPasswordSection: some View {
        Section {
            LabeledTextField(
                viewModel.purpose == .setDuress ? "Duress Password" : "New Password",
                text: $viewModel.newPassword,
                kind: .secure(),
                status: newPasswordStatus,
            )
            .secretTextInput(.verbatim)
            .focused($focusedField, equals: .new)
            .submitLabel(.next)
            .onSubmit {
                focusedField = .confirmation
            }
            .disabled(viewModel.state == .saving)
            .wrongPasswordFeedback(trigger: viewModel.refusedPasswordCount)

            LabeledTextField(
                viewModel.purpose == .setDuress ? "Confirm Duress Password" : "Confirm New Password",
                text: $viewModel.confirmation,
                kind: .secure(),
                status: viewModel.confirmation.isEmpty
                    ? .none
                    : .passwordConfirmation(matches: viewModel.confirmationMatches),
            )
            .secretTextInput(.verbatim)
            .focused($focusedField, equals: .confirmation)
            .submitLabel(.done)
            .onSubmit(submit)
            .disabled(viewModel.state == .saving)
        } footer: {
            Text(
                "Use at least \(AppLockPasswordRules.minimumLength) characters, and not only numbers. Anyone with a copy of your vault could try passwords on a computer, without this iPhone, so a PIN isn't enough.",
            )
        }
    }

    /// Says what's wrong with the new password once the user has moved on from it, not while they're typing it.
    private var newPasswordStatus: LabeledTextField.Status {
        // Until something else is typed: the field is empty, and may be focused again, once it's refused.
        if viewModel.isNewPasswordRefused {
            return .error(message: Self.refusedPasswordMessage)
        }
        guard focusedField != .new else { return .none }
        if viewModel.isNewPasswordSameAsCurrent {
            return .error(message: "Choose a password that's different from the current one.")
        }
        switch viewModel.newPasswordProblem {
        case .tooShort:
            return .error(message: "Use at least \(AppLockPasswordRules.minimumLength) characters.")
        case .onlyNumbers:
            return .error(message: "Use some letters or symbols, not only numbers.")
        case nil:
            return .none
        }
    }

    /// Why the password service refused a duress password. Only the open vault's own App Lock Password is refused.
    private static let refusedPasswordMessage = "Must be different from your App Lock Password."

    // MARK: - Action

    private func actionSection(passwordWait: Duration?) -> some View {
        Section {
            ProminentActionButton(actionTitle, systemImage: actionSystemImage, role: actionRole) {
                focusedField = nil
                await viewModel.submit()
            }
            .disabled(!viewModel.canSubmit || passwordWait != nil)
        } footer: {
            switch viewModel.state {
            case .saving:
                HStack(spacing: 6) {
                    ProgressView()
                    Text(savingMessage)
                }
            case .failed:
                Label(failureMessage, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
            case .editing, .done:
                EmptyView()
            }
        }
    }

    private var savingMessage: String {
        switch viewModel.purpose {
        case .set: "Encrypting your vault with the password."
        case .change, .turnOff: "Checking the password."
        case .setDuress: "Setting the duress password."
        }
    }

    private func submit() {
        guard viewModel.canSubmit, AppLockPasswordWait.remaining(until: viewModel.retryAt) == nil else { return }
        focusedField = nil
        Task { await viewModel.submit() }
    }

    private var actionTitle: String {
        switch viewModel.purpose {
        case .set: "Set App Lock Password"
        case .change: "Change Password"
        case .turnOff: "Turn Off Password"
        case .setDuress: "Set Duress Password"
        }
    }

    private var actionSystemImage: String {
        switch viewModel.purpose {
        case .set, .change, .setDuress: "checkmark.shield.fill"
        case .turnOff: "lock.open.fill"
        }
    }

    private var actionRole: ButtonRole? {
        viewModel.purpose == .turnOff ? .destructive : nil
    }

    private var failureMessage: String {
        switch viewModel.purpose {
        case .set: "Something went wrong. The App Lock Password wasn't set."
        case .change: "Something went wrong. The App Lock Password wasn't changed."
        case .turnOff: "Something went wrong. The App Lock Password is still on."
        case .setDuress: "Something went wrong. The duress password wasn't set."
        }
    }

    // MARK: - Done

    @ViewBuilder
    private var doneSections: some View {
        Section {
            switch viewModel.purpose {
            case .set:
                BackupHeroHeader(
                    title: "App Lock Password Set",
                    subtitle: "Vault will ask for it every time it unlocks.",
                    systemImage: "checkmark.shield.fill",
                    color: .green,
                    bouncesOnAppear: true,
                )
            case .change:
                BackupHeroHeader(
                    title: "App Lock Password Changed",
                    subtitle: "Use the new password from now on.",
                    systemImage: "checkmark.shield.fill",
                    color: .green,
                    bouncesOnAppear: true,
                )
            case .turnOff:
                BackupHeroHeader(
                    title: "App Lock Password Turned Off",
                    subtitle: "Vault will ask only for Face ID, Touch ID or your passcode to unlock.",
                    systemImage: "lock.open.fill",
                    color: .green,
                    bouncesOnAppear: true,
                )
            case .setDuress:
                // The same every time: it never says whether it replaced anything.
                BackupHeroHeader(
                    title: "Duress Password Set",
                    subtitle: "To open its vault, enter it instead of your App Lock Password when Vault unlocks.",
                    systemImage: "checkmark.shield.fill",
                    color: .green,
                    bouncesOnAppear: true,
                )
            }
        }

        if viewModel.purpose == .set || viewModel.purpose == .change {
            Section {
                note(
                    title: "Keep it somewhere safe",
                    detail: "If you forget it, the only way back in is to erase the vault and restore a backup.",
                    systemImage: "lock.doc.fill",
                    color: .secondary,
                )
            }
        }
    }
}

#Preview("Set") {
    NavigationStack {
        AppLockPasswordFormView(
            viewModel: .init(purpose: .set, appLock: .preview(password: nil)),
            close: {},
        )
    }
}

#Preview("Change") {
    NavigationStack {
        AppLockPasswordFormView(
            viewModel: .init(purpose: .change, appLock: .preview(password: "correct horse")),
            close: {},
        )
    }
}

#Preview("Duress password") {
    NavigationStack {
        AppLockPasswordFormView(
            viewModel: .init(purpose: .setDuress, appLock: .preview(password: "correct horse")),
            close: {},
        )
    }
}

#Preview("Turn off, waiting") {
    NavigationStack {
        AppLockPasswordFormView(
            viewModel: .init(purpose: .turnOff, appLock: .preview(password: "correct horse", wrongAttempts: 6)),
            close: {},
        )
    }
}

extension AppLockService {
    /// An app lock with the App Lock Password on offer, kept in memory, for previews. It unlocks itself.
    static func preview(password: String?, wrongAttempts: Int = 0) -> AppLockService {
        let settings = AppLockSettingsStore(userDefaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard)
        let service = AppLockService(
            settings: settings,
            authenticationService: DeviceAuthenticationService(policy: .alwaysAllow),
            passwordService: FakeAppLockPasswordService(
                password: password,
                wrongAttempts: wrongAttempts,
                deadline: .milliseconds(750),
            ),
            purgeSensitiveData: {},
        )
        if let password {
            // A password always starts the lock locked. Settings are only shown unlocked.
            Task {
                await service.unlock()
                await service.unlock(password: password)
            }
        }
        return service
    }
}
