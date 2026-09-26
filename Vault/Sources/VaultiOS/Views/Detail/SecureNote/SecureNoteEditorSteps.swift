import Foundation
import SwiftUI
import VaultFeed

/// The note itself, and how it's formatted.
struct SecureNoteContentStep: View {
    @Bindable var viewModel: SecureNoteDetailViewModel

    var body: some View {
        Section {
            LabeledTextField(
                viewModel.strings.noteContentsTitle,
                text: $viewModel.editingModel.detail.contents,
                prompt: "The first line is the note's title",
                kind: .multiline(minLines: 12),
            )
            .secretTextInput(.prose)
            .font(.subheadline)
            .fontDesign(.monospaced)
        }

        Section {
            Picker(selection: $viewModel.editingModel.detail.textFormat) {
                ForEach(TextFormat.allCases, id: \.self) { format in
                    Text(format.localizedString)
                        .tag(format)
                }
            } label: {
                FormRow(image: Image(systemName: "text.justify.left"), color: .accentColor, style: .standard) {
                    Text("Text Format")
                }
            }
        } footer: {
            Text("Markdown shows headings, lists and links formatted when you view the note.")
        }
    }
}

/// Who can see the note, what its tile shows, and how it's protected.
struct SecureNoteSecurityStep: View {
    @Bindable var viewModel: SecureNoteDetailViewModel

    var body: some View {
        let detail = viewModel.editingModel.detail
        DetailEditorVisibilitySection(
            viewConfig: $viewModel.editingModel.detail.viewConfig,
            passphrase: $viewModel.editingModel.detail.searchPassphrase,
            passphraseValidation: detail.$searchPassphrase,
            hasExistingPassphrase: detail.hasExistingSearchPassphrase,
            explanation: "A hidden note stays out of the feed. It only appears when you search for its passphrase exactly.",
            hiddenWarning: viewModel.strings.passphraseSubtitle,
        )

        DetailEditorPreviewModeSection(
            previewMode: $viewModel.editingModel.detail.previewMode,
            isEncrypted: detail.encrypted,
            explanation: "What the note's tile shows in the feed. Showing less keeps more of it off the screen.",
        )

        DetailEditorLockSection(
            lockState: $viewModel.editingModel.detail.lockState,
            explanation: "A locked note needs Face ID, Touch ID or your passcode to view or edit. Its tile still shows the preview above.",
        )

        DetailEditorEncryptionSection(
            title: "Encryption",
            status: detail.encryptionEnabledText,
            isStatusWarning: false,
            explanation: "Encrypts the note on this device with a password, which you need every time you view it.",
        ) {
            VaultDetailEncryptionEditView(
                title: "Encryption",
                description: "Locks this note cryptographically on your device. Password is required on every view.",
                encryptionInitiallyEnabled: detail.encrypted,
                didSetNewEncryptionPassword: { newPassword in
                    viewModel.editingModel.detail.newEncryptionPassword = newPassword
                },
                didRemoveEncryption: {
                    viewModel.editingModel.detail.newEncryptionPassword = ""
                    viewModel.editingModel.detail.existingEncryptionKey = nil
                },
            )
        }

        DetailEditorKillphraseSection(
            isEnabled: $viewModel.editingModel.detail.killphraseEnabled,
            newKillphrase: $viewModel.editingModel.detail.newKillphrase,
            isValid: detail.isKillphraseValid,
            hasExistingKillphrase: viewModel.editingModel.initialDetail.killphraseEnabled,
            explanation: "A killphrase deletes this note, immediately and quietly, when you search for it exactly. With a passphrase too, the note can be deleted without it ever being shown.",
            enabledWarning: viewModel.strings.killphraseSubtitle,
        )
    }
}
