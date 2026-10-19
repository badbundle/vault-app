import SwiftUI
import VaultCore
import VaultFeed

/// Adds or edits a private key, with the shared editor's model: recognized and checked as it's typed or pasted, always
/// encrypted with a password of its own and locked (G102, G105). An existing key stays masked until clicked, it hides
/// while
/// Vault isn't the active app, and it can't be copied while it's typed.
struct VaultMacPrivateKeyEditor: View {
    @State var viewModel: PrivateKeyDetailViewModel
    var close: () -> Void

    @State private var newPassword = VaultMacNewPassword()
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Private Key") {
                    VaultMacTextField("Title", text: $viewModel.editingModel.detail.title, identifier: "editor.title")
                    keyField
                    VaultMacPrivateKeyValidationLabel(summary: viewModel.validationSummary())
                        .accessibilityIdentifier("editor.validation")
                    VaultMacTextField("Description", text: $viewModel.editingModel.detail.contents)
                }
                Section {
                    VaultMacSecureField(
                        viewModel.editingModel.detail
                            .existingEncryptionKey == nil ? "Password" : "New Password (optional)",
                        text: $newPassword.password, identifier: "editor.encryption-password",
                    )
                    if newPassword.password.isNotEmpty {
                        VaultMacSecureField(
                            "Confirm Password",
                            text: $newPassword.confirmation,
                            identifier: "editor.encryption-password-confirmation",
                        )
                    }
                } header: {
                    Text("Encryption")
                } footer: {
                    Text("A private key is always encrypted with a password of its own, which Vault never stores.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                VaultMacAppearanceSection(
                    color: $viewModel.editingModel.detail.color,
                    tags: $viewModel.editingModel.detail.tags,
                    allTags: viewModel.allTags,
                )
                VaultMacPrivacySection(
                    viewConfig: $viewModel.editingModel.detail.viewConfig,
                    searchPassphrase: $viewModel.editingModel.detail.searchPassphrase,
                    hasExistingSearchPassphrase: viewModel.editingModel.detail.hasExistingSearchPassphrase,
                    killphraseEnabled: $viewModel.editingModel.detail.killphraseEnabled,
                    newKillphrase: $viewModel.editingModel.detail.newKillphrase,
                    lockState: nil,
                )
            }
            .formStyle(.grouped)
            Divider()
            VaultMacEditorButtons(
                canSave: canSave,
                isSaving: viewModel.isSaving,
                deleteConfirmation: viewModel.isInitialCreation
                    ? nil
                    : (viewModel.strings.deleteConfirmTitle, viewModel.strings.deleteConfirmSubtitle),
                cancel: close,
                save: {
                    await viewModel.saveChanges()
                    // A new item's editor closes once it's created, and an existing one's once its changes are saved.
                    if !viewModel.isInitialCreation, !viewModel.editingModel.isDirty {
                        close()
                    }
                },
                delete: { await viewModel.delete() },
            )
        }
        .frame(width: 560, height: 720)
        .onReceive(viewModel.isFinishedPublisher()) { close() }
        .vaultMacEditorErrorAlert(viewModel.didEncounterErrorPublisher())
        .onChange(of: newPassword) {
            viewModel.editingModel.detail.newEncryptionPassword = newPassword.confirmed
        }
        .onChange(of: appearsActive) { _, isActive in
            // An existing key is masked again, as its page masks it. A new one comes back as it was being typed.
            if !isActive, !viewModel.isInitialCreation {
                viewModel.isKeyRevealed = false
            }
        }
    }

    /// The key, typed into a field that can't copy it, or masked: until it's clicked, for an existing key, and
    /// whenever Vault isn't the active app.
    private var keyField: some View {
        LabeledContent("Key") {
            if viewModel.isKeyRevealed, appearsActive {
                VaultMacTextEditor(
                    text: $viewModel.editingModel.detail.key,
                    isMonospaced: true,
                    accessibilityLabel: "Key",
                    identifier: "editor.private-key",
                    copiesText: false,
                )
                .frame(minHeight: 120)
            } else {
                Button {
                    viewModel.isKeyRevealed = true
                } label: {
                    VaultMacMaskedPrivateKey(key: viewModel.editingModel.detail.key, isRevealed: false)
                }
                .buttonStyle(.plain)
                .help("Show Key")
                .accessibilityLabel("Show key")
                .accessibilityIdentifier("editor.private-key-masked")
            }
        }
    }

    private var canSave: Bool {
        viewModel.editingModel.isValid && newPassword.agrees
            && (viewModel.isInitialCreation || viewModel.editingModel.isDirty)
    }
}
