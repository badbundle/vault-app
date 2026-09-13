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
                passwordSection
                generateSection
                warningSection
                detailsSection
            case .denied:
                authenticateSection(isError: true)
            }
        }
        .navigationTitle(Text("Backup Password"))
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(viewModel.newPassword.isLoading)
        .animation(.easeOut, value: viewModel.newlyEnteredPassword.isNotEmpty)
        .task {
            await viewModel.onAppear()
        }
        .onDisappear {
            viewModel.didDisappear()
        }
        .toolbar {
            switch viewModel.newPassword {
            case .initial, .creating, .keygenCancelled, .keygenError, .passwordConfirmError:
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        keyGenerationTask?.cancel()
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .tint(.red)
                    }
                    .disabled(viewModel.newPassword.isLoading)
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
            AsyncButton {
                await viewModel.onAppear()
            } label: {
                FormRow(image: Image(systemName: "key.horizontal.fill"), color: .accentColor) {
                    Text("Authenticate")
                }
            } loading: {
                FormRow(image: Image(systemName: "key.horizontal.fill"), color: .accentColor) {
                    ProgressView()
                }
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
            Text("New Password")
        } footer: {
            Text("Enter a new password to generate an encryption key.")
        }
        .animation(.easeOut, value: viewModel.newlyEnteredPassword)
    }

    // MARK: - Generate Section

    private var generateSection: some View {
        Section {
            Button {
                keyGenerationTask?.cancel()
                keyGenerationTask = Task {
                    await viewModel.saveEnteredPassword()
                }
            } label: {
                FormRow(image: Image(systemName: "key.2.on.ring.fill"), color: .accentColor) {
                    Text("Generate Key")
                }
            }
            .animation(.none, value: viewModel.newPassword)
            .disabled(!viewModel.canGenerateNewPassword)
        } footer: {
            generationStatus
        }
    }

    @ViewBuilder
    private var generationStatus: some View {
        switch viewModel.newPassword {
        case .success:
            Label("Vault encryption key updated successfully", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .keygenError, .keygenCancelled:
            Label("Error generating encryption key", systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        case .creating:
            HStack(alignment: .center, spacing: 4) {
                ProgressView()
                Text("Generating encryption key")
            }
        case .passwordConfirmError:
            Label("Passwords do not match", systemImage: "xmark")
                .foregroundStyle(.red)
        case .initial:
            EmptyView()
        }
    }

    // MARK: - Warning Section

    /// The historical-backup caution is a note, not an action.
    ///
    /// Rendered as a row it read as a tappable control, so it lives in a footer — the standard place
    /// for explanatory copy — with no rows of its own.
    private var warningSection: some View {
        Section {
            EmptyView()
        } header: {
            Text("Historical Backups")
        } footer: {
            Text(
                "Changing your password will not update existing backups. To restore from a previous backup, you must use the password that was active when that backup was created.",
            )
        }
    }

    // MARK: - Details Section

    private var detailsSection: some View {
        Section {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your password is used to generate an encryption key that is used to secure your vault.")
                    Text(
                        "For security, this key generation process may take up to 3 minutes, even on a very fast device.",
                    )
                    Text(
                        "Your encryption key is not shared between devices.",
                    )
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            } label: {
                Label("About", systemImage: "questionmark.circle.fill")
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
