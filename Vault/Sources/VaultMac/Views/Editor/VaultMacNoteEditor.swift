import SwiftUI
import VaultCore
import VaultFeed

/// Adds or edits a note, with the shared editor's model: its first line is its title, as on iOS. It can be encrypted
/// with a password of its own, which is never stored (G42).
struct VaultMacNoteEditor: View {
    @State var viewModel: SecureNoteDetailViewModel
    var close: () -> Void

    @State private var newPassword = VaultMacNewPassword()

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Note") {
                    VaultMacTextEditor(
                        text: $viewModel.editingModel.detail.contents,
                        accessibilityLabel: "Note",
                        identifier: "editor.contents",
                    )
                    .frame(minHeight: 200)
                    Picker("Format", selection: $viewModel.editingModel.detail.textFormat) {
                        Text("Plain Text").tag(TextFormat.plain)
                        Text("Markdown").tag(TextFormat.markdown)
                    }
                    Picker("In the List", selection: $viewModel.editingModel.detail.previewMode) {
                        Text("Title and First Line").tag(NotePreviewMode.titleAndFirstLine)
                        Text("Title Only").tag(NotePreviewMode.titleOnly)
                        Text("Hidden").tag(NotePreviewMode.hidden)
                    }
                }
                VaultMacAppearanceSection(
                    color: $viewModel.editingModel.detail.color,
                    tags: $viewModel.editingModel.detail.tags,
                    allTags: viewModel.allTags,
                )
                encryptionSection
                VaultMacPrivacySection(
                    viewConfig: $viewModel.editingModel.detail.viewConfig,
                    searchPassphrase: $viewModel.editingModel.detail.searchPassphrase,
                    hasExistingSearchPassphrase: viewModel.editingModel.detail.hasExistingSearchPassphrase,
                    killphraseEnabled: $viewModel.editingModel.detail.killphraseEnabled,
                    newKillphrase: $viewModel.editingModel.detail.newKillphrase,
                    lockState: $viewModel.editingModel.detail.lockState,
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
        .frame(width: 560, height: 680)
        .onReceive(viewModel.isFinishedPublisher()) { close() }
        .vaultMacEditorErrorAlert(viewModel.didEncounterErrorPublisher())
        .onChange(of: newPassword) {
            viewModel.editingModel.detail.newEncryptionPassword = newPassword.confirmed
        }
    }

    private var encryptionSection: some View {
        Section {
            if viewModel.editingModel.detail.existingEncryptionKey != nil {
                LabeledContent("Encryption", value: "On")
                Button("Remove Encryption") {
                    newPassword = VaultMacNewPassword()
                    viewModel.editingModel.detail.newEncryptionPassword = ""
                    viewModel.editingModel.detail.existingEncryptionKey = nil
                }
            }
            VaultMacSecureField(
                viewModel.editingModel.detail.existingEncryptionKey == nil ? "Password" : "New Password",
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
            Text(
                "A note with a password of its own opens only with it. Vault never stores the password, so it can't be reset.",
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private var canSave: Bool {
        viewModel.editingModel.isValid && newPassword.agrees
            && (viewModel.isInitialCreation || viewModel.editingModel.isDirty)
    }
}
