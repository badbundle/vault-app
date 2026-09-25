import SwiftUI
import VaultFeed

/// Shows and edits a recovery phrase.
///
/// A recovery phrase is only ever opened after decrypting it with its password, and always opens locked, needing
/// device authentication as well. Once unlocked, the words stay masked until tapped. They're hidden whenever the app
/// isn't in the foreground (so they don't appear in the app switcher) or the screen is being recorded or shared, and
/// the item locks again when the app goes to the background.
@MainActor
struct RecoveryPhraseDetailView: View {
    @State private var viewModel: RecoveryPhraseDetailViewModel
    @Binding private var navigationPath: NavigationPath

    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isSceneCaptured) private var isSceneCaptured
    @State private var selectedColor: Color
    @State private var modal: Modal?
    @State private var currentError: (any Error)?
    @State private var isShowingDeleteConfirmation = false
    @State private var isSeedPassphraseRevealed = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case title
        case contents
        case word(Int)
        case seedPassphrase
    }

    private enum Modal: IdentifiableSelf {
        case editPassword
        case editSearchPassphrase
        case editKillphrase
        case editPreviewMode
        case editTags
    }

    init(
        editingExisting phrase: RecoveryPhrase,
        encryptionKey: DerivedEncryptionKey,
        navigationPath: Binding<NavigationPath>,
        dataModel: VaultDataModel,
        storedMetadata: VaultItem.Metadata,
        editor: any RecoveryPhraseDetailEditor,
        openInEditMode: Bool,
    ) {
        self.init(
            viewModel: .init(
                mode: .editing(phrase: phrase, metadata: storedMetadata, existingKey: encryptionKey),
                dataModel: dataModel,
                editor: editor,
            ),
            navigationPath: navigationPath,
        )
        if openInEditMode {
            viewModel.startEditing()
        }
    }

    init(
        newPhraseWithEditor editor: any RecoveryPhraseDetailEditor,
        navigationPath: Binding<NavigationPath>,
        dataModel: VaultDataModel,
    ) {
        self.init(
            viewModel: .init(mode: .creating, dataModel: dataModel, editor: editor),
            navigationPath: navigationPath,
        )
        viewModel.startEditing()
    }

    init(viewModel: RecoveryPhraseDetailViewModel, navigationPath: Binding<NavigationPath>) {
        _viewModel = .init(initialValue: viewModel)
        _navigationPath = navigationPath
        _selectedColor = .init(initialValue: (viewModel.editingModel.detail.color ?? .default).color)
    }

    var body: some View {
        VaultItemDetailView(
            viewModel: viewModel,
            currentError: $currentError,
            isShowingDeleteConfirmation: $isShowingDeleteConfirmation,
            navigationPath: $navigationPath,
            presentationMode: presentationMode,
        ) {
            if isContentHidden {
                hiddenSection
            } else if viewModel.isInEditMode {
                titleEditingSection
                standardEditingSection
                wordsEditingSection
                seedPassphraseEditingSection
                securityEditingSection
                if viewModel.shouldShowDeleteButton {
                    Section {
                        ProminentActionButton(
                            localized(key: "action.delete.title"),
                            systemImage: "trash.fill",
                            role: .destructive,
                        ) {
                            isShowingDeleteConfirmation = true
                        }
                    }
                }
            } else {
                headerSection
                wordsSection
                if viewModel.editingModel.detail.seedPassphrase.isNotEmpty {
                    seedPassphraseSection
                }
                MetadataDisclosureSection(
                    tags: viewModel.tagsThatAreSelected,
                    entries: viewModel.detailEntries,
                )
            }
        }
        .toolbar {
            // Only for the words: the title and passphrase keep the standard keyboard.
            if let index = focusedWordIndex {
                ToolbarItemGroup(placement: .keyboard) {
                    keyboardToolbar(forWordAt: index)
                }
            }
        }
        .animation(.snappy, value: isContentHidden)
        .animation(.snappy, value: viewModel.editingModel.detail.wordCount)
        .onChange(of: scenePhase) { _, newValue in
            if newValue == .background {
                isSeedPassphraseRevealed = false
                viewModel.lock()
            }
        }
        .onDisappear {
            isSeedPassphraseRevealed = false
            if !viewModel.isInitialCreation {
                viewModel.areWordsRevealed = false
            }
        }
        .onChange(of: selectedColor.hashValue) { _, _ in
            viewModel.editingModel.detail.color = VaultItemColor(color: selectedColor)
        }
        .sheet(item: $modal, onDismiss: nil) { item in
            NavigationStack {
                sheet(for: item)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button {
                                modal = nil
                            } label: {
                                Text("Done")
                            }
                            .disabled(!canDismiss(item))
                        }
                    }
            }
            .interactiveDismissDisabled(!canDismiss(item))
        }
    }

    /// The words are sensitive enough that they shouldn't be visible in the app switcher, a screen recording or a
    /// mirrored screen.
    private var isContentHidden: Bool {
        scenePhase != .active || isSceneCaptured
    }

    private var hiddenSection: some View {
        Section {
            PlaceholderView(
                systemIcon: "eye.slash",
                title: "Hidden",
                subtitle: "Recovery phrases are hidden while Vault isn't in the foreground, or while the screen is being recorded or shared.",
            )
            .padding()
            .containerRelativeFrame(.horizontal)
        }
    }

    // MARK: - Viewing

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(viewModel.visibleTitle)
                    .font(.title2.bold())
                    .multilineTextAlignment(.leading)
                if viewModel.editingModel.detail.contents.isNotBlank {
                    Text(viewModel.editingModel.detail.contents)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .privacySensitive()
                }
                RecoveryPhraseValidationBadge(summary: viewModel.validationSummary())
            }
            .padding(.vertical, 4)
        } header: {
            iconHeader
                .containerRelativeFrame(.horizontal)
                .padding(.vertical, 2)
        }
    }

    private var wordsSection: some View {
        Section {
            wordGrid(highlighting: viewModel.validationSummary().unknownWordPositions)
        } header: {
            Text(viewModel.editingModel.detail.standard.localizedTitle)
        } footer: {
            revealWordsHint
        }
    }

    /// The words, masked until the user taps them.
    private func wordGrid(highlighting unknownWordPositions: Set<Int>) -> some View {
        RecoveryPhraseWordGridView(
            words: viewModel.editingModel.detail.words,
            isRevealed: viewModel.areWordsRevealed,
            highlightedPositions: unknownWordPositions,
            wordNumberLabel: viewModel.strings.wordNumber,
            toggleRevealed: {
                withAnimation(.snappy) {
                    viewModel.areWordsRevealed.toggle()
                }
            },
        )
        .privacySensitive()
        .listRowInsets(EdgeInsets(vertical: 12, horizontal: 12))
    }

    private var revealWordsHint: some View {
        Text(viewModel.areWordsRevealed ? "Tap a word to hide them all." : "Tap a word to reveal them all.")
    }

    private var seedPassphraseSection: some View {
        Section {
            HStack {
                Group {
                    if isSeedPassphraseRevealed {
                        Text(verbatim: viewModel.editingModel.detail.seedPassphrase)
                    } else {
                        Text(verbatim: String(repeating: "•", count: 8))
                            .accessibilityLabel(Text("Hidden"))
                    }
                }
                .font(.body.monospaced())
                .privacySensitive()
                .frame(maxWidth: .infinity, alignment: .leading)

                revealSeedPassphraseButton
            }
        } header: {
            Text("Passphrase")
        }
    }

    private var revealSeedPassphraseButton: some View {
        Button {
            isSeedPassphraseRevealed.toggle()
        } label: {
            Image(systemName: isSeedPassphraseRevealed ? "eye.slash" : "eye")
                .accessibilityLabel(Text(isSeedPassphraseRevealed ? "Hide Passphrase" : "Show Passphrase"))
        }
        .buttonStyle(.borderless)
    }

    private var iconHeader: some View {
        Image(systemName: "list.number")
            .font(.title)
            .foregroundStyle(selectedColor)
    }

    // MARK: - Editing

    private var titleEditingSection: some View {
        Section {
            TextField("Title", text: $viewModel.editingModel.detail.title)
                .focused($focusedField, equals: .title)
                .submitLabel(.next)
                .onSubmit {
                    focusedField = .contents
                }

            TextField("Description", text: $viewModel.editingModel.detail.contents, axis: .vertical)
                .lineLimit(2 ... 8)
                .focused($focusedField, equals: .contents)
                .privacySensitive()
        } header: {
            VStack(spacing: 6) {
                iconHeader
                ColorPicker(selection: $selectedColor, supportsOpacity: false, label: {
                    EmptyView()
                })
                .labelsHidden()
            }
            .containerRelativeFrame(.horizontal)
            .padding(.vertical, 2)
            .padding(.bottom, 4)
        } footer: {
            Text(
                "The title isn't encrypted: anyone who can open Vault can see and search for it, so avoid naming the wallet or what it holds. The description is encrypted along with the words.",
            )
        }
    }

    private var standardEditingSection: some View {
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

    private var wordsEditingSection: some View {
        let summary = viewModel.validationSummary(whileEditingWordAt: focusedWordIndex)
        return Section {
            if viewModel.areWordsRevealed {
                ForEach(viewModel.editingModel.detail.words.indices, id: \.self) { index in
                    let isUnknown = summary.unknownWordPositions.contains(index)
                    wordField(index: index, isUnknown: isUnknown)
                        .listRowBackground(isUnknown ? unknownWordRowBackground : nil)
                }
            } else {
                // Editing an existing phrase would otherwise show every word, so they stay masked until tapped.
                wordGrid(highlighting: summary.unknownWordPositions)
            }
        } header: {
            Text("Words")
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                if !viewModel.areWordsRevealed {
                    revealWordsHint
                }
                RecoveryPhraseValidationBadge(summary: summary)
                    .font(.footnote)
            }
            .padding(.top, 4)
        }
    }

    private var unknownWordRowBackground: some View {
        ZStack {
            Color(UIColor.secondarySystemGroupedBackground)
            Color.orange.opacity(0.2)
        }
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
            .font(.body.monospaced())
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .writingToolsBehavior(.disabled)
            .keyboardType(usesASCIIKeyboard ? .asciiCapable : .default)
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

    private var seedPassphraseEditingSection: some View {
        Section {
            HStack {
                Group {
                    if isSeedPassphraseRevealed {
                        TextField("Passphrase", text: $viewModel.editingModel.detail.seedPassphrase)
                    } else {
                        SecureField("Passphrase", text: $viewModel.editingModel.detail.seedPassphrase)
                    }
                }
                .font(.body.monospaced())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .writingToolsBehavior(.disabled)
                .privacySensitive()
                .focused($focusedField, equals: .seedPassphrase)

                revealSeedPassphraseButton
            }
        } header: {
            Text("Passphrase")
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

    @ViewBuilder
    private var securityEditingSection: some View {
        let detail = viewModel.editingModel.detail
        Section {
            Button {
                modal = .editPassword
            } label: {
                FormRow(image: Image(systemName: "lock.iphone"), color: .accentColor, style: .standard) {
                    LabeledContent("Password") {
                        Text(passwordStateTitle)
                            .foregroundStyle(detail.passwordState == .required ? Color.red : Color.secondary)
                    }
                    .font(.body)
                }
            }

            FormRow(image: Image(systemName: detail.lockState.systemIconName), color: .secondary, style: .standard) {
                LabeledContent("Lock", value: "Always")
                    .font(.body)
            }

            Button {
                modal = .editSearchPassphrase
            } label: {
                FormRow(
                    image: Image(systemName: detail.viewConfig.systemIconName),
                    color: .accentColor,
                    style: .standard,
                ) {
                    LabeledContent("Visibility", value: detail.viewConfig.localizedTitle)
                        .font(.body)
                }
            }

            Button {
                modal = .editPreviewMode
            } label: {
                FormRow(image: Image(systemName: "rectangle.dashed"), color: .accentColor, style: .standard) {
                    LabeledContent("Preview", value: detail.previewMode.localizedTitle)
                        .font(.body)
                }
            }

            Button {
                modal = .editKillphrase
            } label: {
                FormRow(
                    image: Image(systemName: detail.killphraseEnabled ? "bolt.badge.checkmark.fill" : "bolt"),
                    color: .accentColor,
                    style: .standard,
                ) {
                    LabeledContent("Killphrase", value: detail.killphraseEnabledText)
                        .font(.body)
                }
            }

            Button {
                modal = .editTags
            } label: {
                VStack {
                    FormRow(image: Image(systemName: "tag"), color: .accentColor, style: .standard) {
                        LabeledContent("Tags", value: viewModel.strings.tagCount(tags: detail.tags.count))
                            .font(.body)
                    }

                    if viewModel.tagsThatAreSelected.isNotEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .center, spacing: 8) {
                                ForEach(viewModel.tagsThatAreSelected) { tag in
                                    TagPillView(tag: tag, isSelected: true)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .scrollClipDisabled()
                    }
                }
            }
        } footer: {
            if detail.passwordState == .required {
                Text(
                    "Set a password to save. Recovery phrases are always encrypted with a password, and locked with your device passcode.",
                )
            } else {
                Text("Recovery phrases are always encrypted with a password, and locked with your device passcode.")
            }
        }
    }

    private var passwordStateTitle: String {
        switch viewModel.editingModel.detail.passwordState {
        case .required: "Required"
        case .set: "Set"
        case .willChange: "Will Change"
        }
    }

    // MARK: - Sheets

    @ViewBuilder
    private func sheet(for modal: Modal) -> some View {
        switch modal {
        case .editPassword:
            VaultDetailEncryptionEditView(
                title: "Password",
                description: "Recovery phrases are always encrypted on your device. The password is needed every time the phrase is viewed, and can't be recovered if you forget it.",
                hasExistingPassword: viewModel.editingModel.detail.existingEncryptionKey != nil,
                didSetNewEncryptionPassword: { newPassword in
                    viewModel.editingModel.detail.newEncryptionPassword = newPassword
                },
            )
        case .editSearchPassphrase:
            VaultDetailPassphraseEditView(
                title: "Visibility",
                description: "Recovery phrases that require a passphrase are hidden from the main feed. You need to search exactly for your chosen passphrase each time to view this item.",
                hiddenWithPassphraseTitle: viewModel.strings.passphraseSubtitle,
                viewConfig: $viewModel.editingModel.detail.viewConfig,
                passphrase: $viewModel.editingModel.detail.searchPassphrase,
            )
        case .editKillphrase:
            VaultDetailKillphraseEditView(
                title: "Killphrase",
                description: "A killphrase is a secret phrase that is used to immediately delete this recovery phrase. In the search bar, search exactly for this text and the item will be immediately and quietly deleted. Combined with a search passphrase, you can delete an item without it being made visible.",
                hiddenWithKillphraseTitle: viewModel.strings.killphraseSubtitle,
                killphraseEnabled: $viewModel.editingModel.detail.killphraseEnabled,
                newKillphrase: $viewModel.editingModel.detail.newKillphrase,
            )
        case .editPreviewMode:
            VaultDetailNotePreviewEditView(
                title: "Preview",
                description: "Controls what appears in the item's preview tile. The words are never shown, and titles aren't encrypted.",
                isEncrypted: true,
                previewMode: $viewModel.editingModel.detail.previewMode,
            )
        case .editTags:
            VaultDetailTagEditView(
                tagsThatAreSelected: viewModel.tagsThatAreSelected,
                remainingTags: viewModel.remainingTags,
                didAdd: { viewModel.editingModel.detail.tags.insert($0.id) },
                didRemove: { viewModel.editingModel.detail.tags.remove($0.id) },
            )
        }
    }

    private func canDismiss(_ modal: Modal) -> Bool {
        switch modal {
        case .editSearchPassphrase: viewModel.editingModel.detail.isSearchPassphraseValid
        case .editKillphrase: viewModel.editingModel.detail.isKillphraseValid
        case .editPassword, .editPreviewMode, .editTags: true
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
            focusedField = index > 0 ? .word(index - 1) : .contents
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

/// Explains why a recovery phrase can't be created on a device without a passcode.
struct RecoveryPhrasePasscodeRequiredView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                PlaceholderView(
                    systemIcon: "lock.trianglebadge.exclamationmark.fill",
                    title: "Passcode Required",
                    subtitle: "Recovery phrases are always locked with your device passcode. Set up a passcode on this device to store a recovery phrase.",
                )
                .padding()
                .containerRelativeFrame(.horizontal)
            }
        }
        .navigationTitle("Recovery Phrase")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                }
            }
        }
    }
}
