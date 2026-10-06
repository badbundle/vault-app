import SwiftUI
import VaultCore
import VaultFeed

/// Adds or edits a recovery phrase, with the shared editor's model: checked against the BIP39, SLIP-39, Electrum and
/// Monero word lists and checksums, always encrypted with a password of its own and locked (G41). Its words can't be
/// copied while they're typed.
struct VaultMacRecoveryPhraseEditor: View {
    @State var viewModel: RecoveryPhraseDetailViewModel
    var close: () -> Void

    @State private var newPassword = VaultMacNewPassword()

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Recovery Phrase") {
                    VaultMacTextField("Title", text: $viewModel.editingModel.detail.title, identifier: "editor.title")
                    Picker("Standard", selection: Binding(
                        get: { viewModel.editingModel.detail.standard },
                        set: { viewModel.editingModel.detail.setStandard($0) },
                    )) {
                        ForEach(RecoveryPhraseStandard.allCases, id: \.self) { standard in
                            Text(standard.localizedTitle).tag(standard)
                        }
                    }
                    Picker("Words", selection: Binding(
                        get: { viewModel.editingModel.detail.wordCount },
                        set: { viewModel.editingModel.detail.setWordCount($0) },
                    )) {
                        ForEach(viewModel.editingModel.detail.standard.supportedWordCounts, id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                    words
                    let summary = viewModel.validationSummary()
                    Label(summary.title, systemImage: summary.systemIconName)
                        .foregroundStyle(summary.kind == .valid ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                        .accessibilityIdentifier("editor.validation")
                    VaultMacSecureField("Passphrase (optional)", text: $viewModel.editingModel.detail.seedPassphrase)
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
                    Text("A recovery phrase is always encrypted with a password of its own, which Vault never stores.")
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
    }

    private var words: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
            ForEach(0 ..< viewModel.editingModel.detail.wordCount, id: \.self) { position in
                // A secure field for each word, so none can be copied or learned as it's typed.
                HStack(spacing: 6) {
                    Text("\(position + 1).")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 26, alignment: .trailing)
                    VaultMacSecureField(
                        "Word \(position + 1)",
                        text: Binding(
                            get: { viewModel.editingModel.detail.words[position] },
                            set: { _ = viewModel.editingModel.detail.applyInput($0, at: position) },
                        ),
                        isLabelled: false,
                        identifier: "editor.word.\(position + 1)",
                    )
                }
            }
        }
    }

    private var canSave: Bool {
        viewModel.editingModel.isValid && newPassword.agrees
            && (viewModel.isInitialCreation || viewModel.editingModel.isDirty)
    }
}
