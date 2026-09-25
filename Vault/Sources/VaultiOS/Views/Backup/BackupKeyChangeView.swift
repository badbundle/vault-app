import Foundation
import SwiftUI
import VaultFeed

@MainActor
struct BackupKeyChangeView: View {
    @State private var viewModel: BackupKeyChangeViewModel
    @State private var keyGenerationTask: Task<Void, Never>?

    @Environment(\.dismiss) private var dismiss

    init(viewModel: BackupKeyChangeViewModel) {
        _viewModel = .init(wrappedValue: viewModel)
    }

    var body: some View {
        Form {
            switch viewModel.permissionState {
            case .undetermined:
                authenticateSection(isError: false)
            case .allowed:
                if viewModel.newPassword == .success {
                    successSections
                } else {
                    currentPasswordSection
                    passwordSection
                    setPasswordSection
                    detailsSection
                }
            case .denied:
                authenticateSection(isError: true)
            }
        }
        .navigationTitle(Text("Backup Password"))
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(viewModel.newPassword.isLoading)
        .animation(.snappy, value: viewModel.newlyEnteredPassword.isNotEmpty)
        .animation(.snappy, value: viewModel.newPassword == .success)
        .sensoryFeedback(.success, trigger: viewModel.newPassword) { _, newValue in
            newValue == .success
        }
        .task {
            await viewModel.onAppear()
        }
        .onDisappear {
            // A dismissed view must never complete the key change in the
            // background: cancel any in-flight keygen before resetting.
            keyGenerationTask?.cancel()
            viewModel.didDisappear()
        }
        .toolbar {
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
                    .disabled(viewModel.newPassword.isLoading)
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

    // MARK: - Current Password Section

    /// Makes it clear that a password is already set, so setting another replaces it.
    @ViewBuilder
    private var currentPasswordSection: some View {
        if viewModel.currentPasswordStatus.isSet {
            Section {
                BackupPasswordStatusRow(status: viewModel.currentPasswordStatus)
            }
        }
    }

    // MARK: - Password Section

    private var passwordSection: some View {
        Section {
            SecureField("New Password", text: $viewModel.newlyEnteredPassword)
                .disabled(viewModel.newPassword.isLoading)

            if viewModel.newlyEnteredPassword.isNotEmpty {
                HStack {
                    SecureField("Confirm Password", text: $viewModel.newlyEnteredPasswordConfirm)

                    Image(
                        systemName: viewModel
                            .passwordConfirmMatches ? "checkmark.circle.fill" : "xmark.circle.fill",
                    )
                    .foregroundStyle(viewModel.passwordConfirmMatches ? .green : .red)
                }
                .disabled(viewModel.newPassword.isLoading)
            }
        } header: {
            Text(viewModel.currentPasswordStatus.isSet ? "New Password" : "Backup Password")
        } footer: {
            Text(
                "Backups are encrypted with this password. You will need it to restore a backup, so keep it somewhere safe.",
            )
        }
        .animation(.snappy, value: viewModel.newlyEnteredPassword)
    }

    @ViewBuilder
    private var setPasswordSection: some View {
        if viewModel.newlyEnteredPassword.isNotEmpty {
            Section {
                ProminentActionButton(
                    viewModel.currentPasswordStatus.isSet ? "Change Backup Password" : "Set Backup Password",
                    systemImage: "checkmark.shield.fill",
                ) {
                    keyGenerationTask?.cancel()
                    keyGenerationTask = Task {
                        await viewModel.saveEnteredPassword()
                    }
                }
                .animation(.none, value: viewModel.newPassword)
                .disabled(!viewModel.canSetBackupPassword)
            } footer: {
                setPasswordStatus
            }
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
            BackupConfirmationHeader(
                title: viewModel.didReplaceExistingPassword ? "Backup Password Changed" : "Backup Password Set",
                subtitle: "Your backups will be encrypted with this password from now on.",
                systemImage: "checkmark.shield.fill",
                color: .green,
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

    private var detailsSection: some View {
        Section {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        "Your password is turned into an encryption key on this device. The password itself is never stored.",
                    )
                    Text(
                        "Preparing the key is deliberately slow to resist guessing — up to 3 minutes, even on a fast device.",
                    )
                    Text(
                        "Each device prepares its own key. Keys are never shared between devices.",
                    )
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            } label: {
                Label("About", systemImage: "questionmark.circle.fill")
            }

            DisclosureGroup {
                Text(
                    "Changing your password will not update existing backups. To restore from a previous backup, you must use the password that was active when that backup was created.",
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            } label: {
                Label("Historical Backups", systemImage: "clock.arrow.circlepath")
            }

            DisclosureGroup {
                LabeledContent {
                    Text(viewModel.encryptionKeyDeriverSignature.userVisibleDescription)
                } label: {
                    Text("Algorithm")
                }

                LabeledContent {
                    Text(viewModel.encryptionKeyDeriverSignature.id)
                        .font(.caption2)
                        .fontDesign(.monospaced)
                } label: {
                    Text("ID")
                }
            } label: {
                Label("Keygen Information", systemImage: "key.horizontal.fill")
            }

            #if DEBUG
            DisclosureGroup {
                AsyncButton {
                    await viewModel.loadExistingPassword()
                } label: {
                    Text("Fetch existing password")
                } loading: {
                    ProgressView()
                }
            } label: {
                Text("DEBUG: Keygen Information")
            }
            .foregroundStyle(.secondary)
            #endif
        } header: {
            Text("Details")
        } footer: {
            Text("Encryption algorithm and key generation info.")
        }
    }
}
