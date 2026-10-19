import Foundation
import SwiftUI
import VaultFeed

/// The key itself, checked as it's typed or pasted.
///
/// The key of an existing item stays masked until tapped, so opening the editor doesn't show it. It's never copied,
/// even while it's typed: Cut and Copy do nothing in its field, which wraps the key without hyphenating it
/// (`PrivateKeyTextEditor`).
struct PrivateKeyKeyStep: View {
    @Bindable var viewModel: PrivateKeyDetailViewModel

    var body: some View {
        let summary = viewModel.validationSummary()
        Section {
            if viewModel.isKeyRevealed {
                PrivateKeyTextEditor(text: $viewModel.editingModel.detail.key, accessibilityLabel: "Private Key")
                    .secretTextInput(.verbatim)
                    .privacySensitive()
                    .overlay(alignment: .topLeading) {
                        if viewModel.editingModel.detail.key.isEmpty {
                            Text("Paste or type the key")
                                .foregroundStyle(Color(uiColor: .placeholderText))
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(.vertical, 4)
            } else {
                PrivateKeyTextView(
                    key: viewModel.editingModel.detail.key,
                    isRevealed: false,
                    toggleRevealed: {
                        withAnimation(.snappy) {
                            viewModel.isKeyRevealed = true
                        }
                    },
                )
                .privacySensitive()
                .listRowInsets(EdgeInsets(vertical: 12, horizontal: 12))
            }
        } header: {
            Text("Key")
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                if !viewModel.isKeyRevealed {
                    Text("Tap the key to reveal it.")
                }
                PrivateKeyValidationBadge(summary: summary)
                    .font(.footnote)
                Text(
                    "Vault checks WIF keys, extended private keys (xprv, zprv and others), raw hex keys, Nostr nsec keys, and OpenPGP, OpenSSH and PEM private keys. It keeps anything else exactly as you enter it.",
                )
            }
            .padding(.top, 4)
        }
    }
}

/// What the key is called, and a description that's encrypted with it.
struct PrivateKeyNameStep: View {
    @Bindable var viewModel: PrivateKeyDetailViewModel
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case title
        case contents
    }

    var body: some View {
        Section {
            LabeledTextField("Title", text: $viewModel.editingModel.detail.title)
                .secretTextInput(.prose)
                .focused($focusedField, equals: .title)
                .submitLabel(.next)
                .onSubmit {
                    focusedField = .contents
                }

            LabeledTextField(
                "Description",
                text: $viewModel.editingModel.detail.contents,
                kind: .multiline(minLines: 2),
            )
            .secretTextInput(.prose)
            .focused($focusedField, equals: .contents)
            .privacySensitive()
        } footer: {
            Text(
                "The title isn't encrypted: anyone who can open Vault can see and search for it, so avoid naming the wallet or what the key unlocks. The description is encrypted along with the key.",
            )
        }
    }
}

/// The key's password, who can see it, and what its tile shows.
struct PrivateKeySecurityStep: View {
    @Bindable var viewModel: PrivateKeyDetailViewModel

    var body: some View {
        let detail = viewModel.editingModel.detail
        DetailEditorEncryptionSection(
            title: "Password",
            status: passwordStateTitle,
            isStatusWarning: detail.passwordState == .required,
            explanation: detail.passwordState == .required
                ? "Set a password to save. Private keys are always encrypted with a password, and locked with your device passcode."
                : "Private keys are always encrypted with a password, and locked with your device passcode.",
        ) {
            VaultDetailEncryptionEditView(
                title: "Password",
                description: "Private keys are always encrypted on your device. The password is needed every time the key is viewed, and can't be recovered if you forget it.",
                hasExistingPassword: detail.existingEncryptionKey != nil,
                didSetNewEncryptionPassword: { newPassword in
                    viewModel.editingModel.detail.newEncryptionPassword = newPassword
                },
            )
        }

        Section {
            FormRow(image: Image(systemName: detail.lockState.systemIconName), color: .secondary, style: .standard) {
                LabeledContent("Lock", value: "Always")
            }
        } footer: {
            Text("A private key always needs Face ID, Touch ID or your passcode to view.")
        }

        DetailEditorVisibilitySection(
            viewConfig: $viewModel.editingModel.detail.viewConfig,
            passphrase: $viewModel.editingModel.detail.searchPassphrase,
            passphraseValidation: detail.$searchPassphrase,
            hasExistingPassphrase: detail.hasExistingSearchPassphrase,
            explanation: "A hidden private key stays out of the feed. It only appears while the whole search is its passphrase, in any capitals.",
            hiddenWarning: viewModel.strings.passphraseSubtitle,
        )

        DetailEditorPreviewModeSection(
            previewMode: $viewModel.editingModel.detail.previewMode,
            isEncrypted: true,
            explanation: "What the key's tile shows in the feed. The key is never shown, and the title isn't encrypted.",
        )

        DetailEditorKillphraseSection(
            isEnabled: $viewModel.editingModel.detail.killphraseEnabled,
            newKillphrase: $viewModel.editingModel.detail.newKillphrase,
            isValid: detail.isKillphraseValid,
            hasExistingKillphrase: viewModel.editingModel.initialDetail.killphraseEnabled,
            explanation: "A killphrase deletes this private key, immediately and quietly, as soon as the search is exactly the phrase, even partway through typing something longer. With a passphrase too, it can be deleted without it ever being shown.",
            enabledWarning: viewModel.strings.killphraseSubtitle,
        )
    }

    private var passwordStateTitle: String {
        switch viewModel.editingModel.detail.passwordState {
        case .required: "Required"
        case .set: "Set"
        case .willChange: "Will Change"
        }
    }
}
