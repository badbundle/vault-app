import Foundation
import SwiftUI
import VaultFeed

/// The phrase itself: its type, the words, and the optional passphrase.
///
/// The words of an existing phrase stay masked until tapped, so opening the editor doesn't show them all at once.
/// While a word is being typed, the keyboard suggests completions from the wordlist.
struct RecoveryPhraseWordsStep: View {
    @Bindable var viewModel: RecoveryPhraseDetailViewModel
    @Binding var isSeedPassphraseRevealed: Bool
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case word(Int)
        case seedPassphrase
    }

    var body: some View {
        standardSection
        wordsSection
        seedPassphraseSection
            .toolbar {
                // Only for the words: the passphrase keeps the standard keyboard.
                if let index = focusedWordIndex {
                    ToolbarItemGroup(placement: .keyboard) {
                        keyboardToolbar(forWordAt: index)
                    }
                }
            }
    }

    // MARK: - Type

    private var standardSection: some View {
        Section {
            Picker(selection: standardBinding) {
                ForEach(RecoveryPhraseStandard.allCases, id: \.self) { standard in
                    Text(standard.localizedTitle)
                        .tag(standard)
                }
            } label: {
                FormRow(image: Image(systemName: "checklist"), color: .accentColor, style: .standard) {
                    Text("Type")
                }
            }

            wordCountRow
        } footer: {
            Text(viewModel.editingModel.detail.standard.localizedSubtitle)
        }
    }

    @ViewBuilder
    private var wordCountRow: some View {
        let detail = viewModel.editingModel.detail
        let wordCountLabel = FormRow(image: Image(systemName: "number"), color: .accentColor, style: .standard) {
            Text("Words")
        }
        if detail.standard == .other {
            Stepper(value: wordCountBinding, in: RecoveryPhraseStandard.otherWordCountRange) {
                FormRow(image: Image(systemName: "number"), color: .accentColor, style: .standard) {
                    LabeledContent("Words", value: detail.wordCount.formatted())
                }
            }
        } else if detail.standard.supportedWordCounts.count > 1 {
            Picker(selection: wordCountBinding) {
                ForEach(detail.standard.supportedWordCounts, id: \.self) { count in
                    Text(count.formatted())
                        .tag(count)
                }
            } label: {
                wordCountLabel
            }
        } else {
            LabeledContent {
                Text(detail.wordCount.formatted())
            } label: {
                wordCountLabel
            }
        }
    }

    // MARK: - Words

    private var wordsSection: some View {
        let summary = viewModel.validationSummary(whileEditingWordAt: focusedWordIndex)
        return Section {
            if viewModel.areWordsRevealed {
                ForEach(viewModel.editingModel.detail.words.indices, id: \.self) { index in
                    let isUnknown = summary.unknownWordPositions.contains(index)
                    wordField(index: index, isUnknown: isUnknown)
                        .listRowBackground(DetailEditorRowBackground(tint: isUnknown ? .orange : nil))
                }
            } else {
                RecoveryPhraseWordGridView(
                    words: viewModel.editingModel.detail.words,
                    isRevealed: false,
                    highlightedPositions: summary.unknownWordPositions,
                    wordNumberLabel: viewModel.strings.wordNumber,
                    toggleRevealed: {
                        withAnimation(.snappy) {
                            viewModel.areWordsRevealed = true
                        }
                    },
                )
                .privacySensitive()
                .listRowInsets(EdgeInsets(vertical: 12, horizontal: 12))
            }
        } header: {
            Text("Words")
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                if !viewModel.areWordsRevealed {
                    Text("Tap a word to reveal them all.")
                }
                RecoveryPhraseValidationBadge(summary: summary)
                    .font(.footnote)
            }
            .padding(.top, 4)
        }
        .animation(.snappy, value: viewModel.editingModel.detail.wordCount)
    }

    private func wordField(index: Int, isUnknown: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack(alignment: .trailing) {
                Text(verbatim: "88")
                    .hidden()
                Text(verbatim: "\(index + 1)")
            }
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)

            TextField(text: wordBinding(at: index)) {
                Text(viewModel.strings.wordNumber(index + 1))
            }
            // VoiceOver doesn't read a text field's label, which only shows as the placeholder while the field is
            // empty, so the field is named for it too. The number beside it is hidden from VoiceOver.
            .accessibilityLabel(viewModel.strings.wordNumber(index + 1))
            .font(.body.monospaced())
            .secretTextInput(SecretTextInput(capitalization: .never, isASCIIOnly: usesASCIIKeyboard))
            .privacySensitive()
            .focused($focusedField, equals: .word(index))
            .submitLabel(index == viewModel.editingModel.detail.wordCount - 1 ? .done : .next)
            .onSubmit {
                focusedField = nextField(after: index)
            }

            if isUnknown {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel(Text("Not in the wordlist"))
            }
        }
    }

    // MARK: - Passphrase

    private var seedPassphraseSection: some View {
        Section {
            LabeledTextField(
                "Passphrase",
                text: $viewModel.editingModel.detail.seedPassphrase,
                kind: .secure(isRevealed: $isSeedPassphraseRevealed),
            )
            .fontDesign(.monospaced)
            .secretTextInput(.verbatim)
            .privacySensitive()
            .focused($focusedField, equals: .seedPassphrase)
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if !viewModel.editingModel.detail.isSeedPassphraseAllowedByStandard {
                    Label(
                        "SLIP-39 passphrases can only use unaccented letters, digits, spaces and common symbols (printable ASCII), so wallets may not accept this one.",
                        systemImage: "exclamationmark.triangle.fill",
                    )
                    .foregroundStyle(.orange)
                }
                if viewModel.editingModel.detail.seedPassphraseHasSurroundingWhitespace {
                    Label(
                        "The passphrase starts or ends with a space. This is part of the passphrase, so make sure it's intended.",
                        systemImage: "exclamationmark.triangle.fill",
                    )
                    .foregroundStyle(.orange)
                }
                Text(
                    "Optional. Also called the 25th word, seed extension or seed offset. Only add one if your wallet uses it.",
                )
            }
        }
    }

    // MARK: - Keyboard

    /// Completions from the wordlist, to fill in the word with a tap, and buttons to move between the words.
    @ViewBuilder
    private func keyboardToolbar(forWordAt index: Int) -> some View {
        ForEach(viewModel.suggestions(forWordAt: index), id: \.self) { suggestion in
            Button {
                viewModel.editingModel.detail.applyInput(suggestion, at: index)
                focusedField = nextField(after: index)
            } label: {
                Text(verbatim: suggestion)
                    .font(.body.monospaced())
            }
        }

        Spacer()

        Button {
            focusedField = index > 0 ? .word(index - 1) : nil
        } label: {
            Image(systemName: "chevron.up")
                .accessibilityLabel(Text("Previous Word"))
        }

        Button {
            focusedField = nextField(after: index)
        } label: {
            Image(systemName: "chevron.down")
                .accessibilityLabel(Text("Next Word"))
        }
    }

    private var focusedWordIndex: Int? {
        if case let .word(index) = focusedField {
            index
        } else {
            nil
        }
    }

    private func nextField(after index: Int) -> Field? {
        index + 1 < viewModel.editingModel.detail.wordCount ? .word(index + 1) : nil
    }

    /// Only SLIP-39, Electrum (in practice) and Monero phrases are always ASCII: BIP39 has wordlists in other scripts.
    private var usesASCIIKeyboard: Bool {
        switch viewModel.editingModel.detail.standard {
        case .slip39, .monero: true
        case .bip39, .electrum, .other: false
        }
    }

    // MARK: - Bindings

    private func wordBinding(at index: Int) -> Binding<String> {
        Binding {
            let words = viewModel.editingModel.detail.words
            return words.indices.contains(index) ? words[index] : ""
        } set: { newValue in
            if let next = viewModel.editingModel.detail.applyInput(newValue, at: index) {
                focusedField = .word(next)
            }
        }
    }

    private var standardBinding: Binding<RecoveryPhraseStandard> {
        Binding {
            viewModel.editingModel.detail.standard
        } set: { newValue in
            viewModel.editingModel.detail.setStandard(newValue)
        }
    }

    private var wordCountBinding: Binding<Int> {
        Binding {
            viewModel.editingModel.detail.wordCount
        } set: { newValue in
            viewModel.editingModel.detail.setWordCount(newValue)
        }
    }
}

/// What the phrase is called, and a description that's encrypted with it.
struct RecoveryPhraseNameStep: View {
    @Bindable var viewModel: RecoveryPhraseDetailViewModel
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
                "The title isn't encrypted: anyone who can open Vault can see and search for it, so avoid naming the wallet or what it holds. The description is encrypted along with the words.",
            )
        }
    }
}

/// The phrase's password, who can see it, and what its tile shows.
struct RecoveryPhraseSecurityStep: View {
    @Bindable var viewModel: RecoveryPhraseDetailViewModel

    var body: some View {
        let detail = viewModel.editingModel.detail
        DetailEditorEncryptionSection(
            title: "Password",
            status: passwordStateTitle,
            isStatusWarning: detail.passwordState == .required,
            explanation: detail.passwordState == .required
                ? "Set a password to save. Recovery phrases are always encrypted with a password, and locked with your device passcode."
                : "Recovery phrases are always encrypted with a password, and locked with your device passcode.",
        ) {
            VaultDetailEncryptionEditView(
                title: "Password",
                description: "Recovery phrases are always encrypted on your device. The password is needed every time the phrase is viewed, and can't be recovered if you forget it.",
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
            Text("A recovery phrase always needs Face ID, Touch ID or your passcode to view.")
        }

        DetailEditorVisibilitySection(
            viewConfig: $viewModel.editingModel.detail.viewConfig,
            passphrase: $viewModel.editingModel.detail.searchPassphrase,
            passphraseValidation: detail.$searchPassphrase,
            hasExistingPassphrase: detail.hasExistingSearchPassphrase,
            explanation: "A hidden recovery phrase stays out of the feed. It only appears when you search for its passphrase exactly.",
            hiddenWarning: viewModel.strings.passphraseSubtitle,
        )

        DetailEditorPreviewModeSection(
            previewMode: $viewModel.editingModel.detail.previewMode,
            isEncrypted: true,
            explanation: "What the phrase's tile shows in the feed. The words are never shown, and the title isn't encrypted.",
        )

        DetailEditorKillphraseSection(
            isEnabled: $viewModel.editingModel.detail.killphraseEnabled,
            newKillphrase: $viewModel.editingModel.detail.newKillphrase,
            isValid: detail.isKillphraseValid,
            hasExistingKillphrase: viewModel.editingModel.initialDetail.killphraseEnabled,
            explanation: "A killphrase deletes this recovery phrase, immediately and quietly, when you search for it exactly. With a passphrase too, it can be deleted without it ever being shown.",
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
