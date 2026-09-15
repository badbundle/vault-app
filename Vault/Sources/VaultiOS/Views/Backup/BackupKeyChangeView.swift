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
                setPasswordSection
                detailsSection
            case .denied:
                authenticateSection(isError: true)
            }
        }
        .navigationTitle(Text("Backup Password"))
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(viewModel.newPassword.isLoading)
        .animation(.snappy, value: viewModel.newlyEnteredPassword.isNotEmpty)
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
            Text("Backup Password")
        } footer: {
            Text(
                "Backups are encrypted with this password. You will need it to restore a backup, so keep it somewhere safe.",
            )
        }
        .animation(.snappy, value: viewModel.newlyEnteredPassword)
    }

    // MARK: - Set Password Section

    private var setPasswordSection: some View {
        Section {
            Button {
                keyGenerationTask?.cancel()
                keyGenerationTask = Task {
                    await viewModel.saveEnteredPassword()
                }
            } label: {
                FormRow(image: Image(systemName: "checkmark.shield.fill"), color: .accentColor) {
                    Text("Set Backup Password")
                }
            }
            .animation(.none, value: viewModel.newPassword)
            .disabled(!viewModel.canSetBackupPassword)
        } footer: {
            setPasswordStatus
        }
    }

    @ViewBuilder
    private var setPasswordStatus: some View {
        switch viewModel.newPassword {
        case .success:
            Label("Backup password set", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
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
        case .initial:
            EmptyView()
        }
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
