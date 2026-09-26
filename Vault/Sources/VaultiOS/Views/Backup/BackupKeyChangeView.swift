import Foundation
import SwiftUI
import VaultFeed

/// Sets or changes the backup password.
///
/// Owns its `NavigationStack` so that pushing the details page doesn't count as leaving: the
/// lifecycle below (authenticate on appear, cancel and clear on disappear) only runs when the whole
/// screen is presented or dismissed.
@MainActor
struct BackupKeyChangeView: View {
    @State private var viewModel: BackupKeyChangeViewModel
    @State private var keyGenerationTask: Task<Void, Never>?
    @FocusState private var focusedField: PasswordField?

    @Environment(\.dismiss) private var dismiss

    private enum PasswordField {
        case new, confirm
    }

    init(viewModel: BackupKeyChangeViewModel) {
        _viewModel = .init(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            form
                .navigationTitle(Text("Backup Password"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
        }
        .interactiveDismissDisabled(viewModel.newPassword.isLoading)
        .task {
            await viewModel.onAppear()
        }
        .onDisappear {
            // A dismissed view must never complete the key change in the
            // background: cancel any in-flight keygen before resetting.
            keyGenerationTask?.cancel()
            viewModel.didDisappear()
        }
    }

    private var form: some View {
        Form {
            switch viewModel.permissionState {
            case .undetermined:
                authenticateSection(isError: false)
            case .allowed:
                if viewModel.newPassword == .success {
                    successSections
                } else {
                    headerSection
                    passwordSection
                    setPasswordSection
                    detailsSection
                }
            case .denied:
                authenticateSection(isError: true)
            }
        }
        .animation(.snappy, value: viewModel.newlyEnteredPassword.isNotEmpty)
        .animation(.snappy, value: viewModel.newPassword == .success)
        .sensoryFeedback(.success, trigger: viewModel.newPassword) { _, newValue in
            newValue == .success
        }
        .onChange(of: viewModel.permissionState) { _, newValue in
            // Choosing a password is the one thing to do here, so start typing straight away.
            if newValue == .allowed {
                focusedField = .new
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        switch viewModel.newPassword {
        case .initial, .creating, .keygenCancelled, .keygenError, .passwordConfirmError:
            ToolbarItem(placement: .cancellationAction) {
                // Deliberately enabled while the keygen runs: with
                // interactive dismissal disabled, this is the only
                // escape hatch from the up-to-3-minute derivation.
                Button {
                    keyGenerationTask?.cancel()
                    dismiss()
                } label: {
                    Text("Cancel")
                        .tint(.red)
                }
            }
        case .success:
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                }
            }
        }
    }

    // MARK: - Authenticate Section

    private func authenticateSection(isError: Bool) -> some View {
        Section {
            ProminentActionButton("Authenticate", systemImage: "key.horizontal.fill") {
                await viewModel.onAppear()
            }
        } header: {
            Text(isError ? "Authentication Failed" : "Locked")
        } footer: {
            Text(
                isError
                    ? "Unable to verify your identity. Please try again."
                    : "Authenticate to change the backup password.",
            )
            .foregroundStyle(isError ? Color.red : Color.secondary)
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        Section {
            BackupHeroHeader(
                title: isChangingPassword ? "Choose a New Password" : "Choose a Backup Password",
                subtitle: "Your backups are encrypted with this password. Keep it somewhere safe.",
                systemImage: "lock.shield.fill",
                color: .accentColor,
                iconSize: 56,
            ) {
                if case let .set(metadata) = viewModel.currentPasswordStatus {
                    currentPasswordLabel(lastSetDate: metadata.lastSetDate)
                }
            }
        }
    }

    /// Makes it clear that a password is already set, so choosing another replaces it.
    private func currentPasswordLabel(lastSetDate: Date?) -> some View {
        // Not a `Label`: inside a form row, its icon takes the row's icon column width.
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            if let lastSetDate {
                Text("Current password set \(lastSetDate.formatted(date: .abbreviated, time: .shortened))")
            } else {
                Text("A backup password is already set")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.fill.tertiary, in: .capsule)
    }

    private var isChangingPassword: Bool {
        viewModel.currentPasswordStatus.isSet
    }

    // MARK: - Password Section

    private var passwordSection: some View {
        Section {
            LabeledTextField("New Password", text: $viewModel.newlyEnteredPassword, kind: .secure())
                .secretTextInput(.verbatim)
                .focused($focusedField, equals: .new)
                .submitLabel(.next)
                .onSubmit {
                    focusedField = .confirm
                }
                .disabled(viewModel.newPassword.isLoading)

            if viewModel.newlyEnteredPassword.isNotEmpty {
                LabeledTextField(
                    "Confirm Password",
                    text: $viewModel.newlyEnteredPasswordConfirm,
                    kind: .secure(),
                    status: .passwordConfirmation(matches: viewModel.passwordConfirmMatches),
                )
                .secretTextInput(.verbatim)
                .focused($focusedField, equals: .confirm)
                .submitLabel(.done)
                .onSubmit(saveEnteredPassword)
                .disabled(viewModel.newPassword.isLoading)
            }
        }
        .animation(.snappy, value: viewModel.newlyEnteredPassword)
    }

    @ViewBuilder
    private var setPasswordSection: some View {
        if viewModel.newlyEnteredPassword.isNotEmpty {
            Section {
                ProminentActionButton(
                    isChangingPassword ? "Change Backup Password" : "Set Backup Password",
                    systemImage: "checkmark.shield.fill",
                ) {
                    saveEnteredPassword()
                }
                .animation(.none, value: viewModel.newPassword)
                .disabled(!viewModel.canSetBackupPassword)
            } footer: {
                setPasswordStatus
            }
        }
    }

    private func saveEnteredPassword() {
        guard viewModel.canSetBackupPassword else { return }
        focusedField = nil
        keyGenerationTask?.cancel()
        keyGenerationTask = Task {
            await viewModel.saveEnteredPassword()
        }
    }

    @ViewBuilder
    private var setPasswordStatus: some View {
        switch viewModel.newPassword {
        case .keygenError:
            Label("Something went wrong. Your backup password was not changed.", systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        case .keygenCancelled:
            Label("Cancelled. Your backup password was not changed.", systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        case .creating:
            HStack(alignment: .center, spacing: 4) {
                ProgressView()
                Text("Securing your password. This can take up to 3 minutes.")
            }
        case .passwordConfirmError:
            Label("Passwords do not match", systemImage: "xmark")
                .foregroundStyle(.red)
        case .initial, .success:
            // Success replaces the whole form with `successSections`.
            EmptyView()
        }
    }

    // MARK: - Success Sections

    @ViewBuilder
    private var successSections: some View {
        Section {
            BackupHeroHeader(
                title: viewModel.didReplaceExistingPassword ? "Backup Password Changed" : "Backup Password Set",
                subtitle: "Your backups will be encrypted with this password from now on.",
                systemImage: "checkmark.shield.fill",
                color: .green,
                bouncesOnAppear: true,
            )
        }

        Section {
            successNote(
                title: "Keep it somewhere safe",
                detail: "You'll need it to restore a backup. It can't be recovered if you forget it.",
                systemImage: "lock.doc.fill",
            )

            if viewModel.didReplaceExistingPassword {
                successNote(
                    title: "Older backups keep their password",
                    detail: "Backups made before now still need the password that was set when they were made.",
                    systemImage: "clock.arrow.circlepath",
                )
            }
        }
    }

    private func successNote(title: String, detail: String, systemImage: String) -> some View {
        FormRow(
            image: Image(systemName: systemImage),
            color: .secondary,
            style: .standard,
            alignment: .firstTextBaseline,
        ) {
            TextAndSubtitle(title: title, subtitle: detail)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Details Section

    /// One quiet row, so the explanations don't compete with the password fields.
    private var detailsSection: some View {
        Section {
            NavigationLink {
                BackupPasswordDetailsView(viewModel: viewModel)
            } label: {
                FormRow(image: Image(systemName: "info.circle"), color: .accentColor, style: .standard) {
                    Text("About Backup Passwords")
                }
            }
        }
    }
}
