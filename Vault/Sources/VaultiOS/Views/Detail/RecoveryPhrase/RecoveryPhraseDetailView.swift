import SwiftUI
import VaultFeed

/// Shows and edits a recovery phrase.
///
/// A recovery phrase is only ever opened after decrypting it with its password, and always opens locked, needing
/// device authentication as well. Once unlocked, the words stay masked until tapped. They're hidden whenever the app
/// isn't in the foreground (so they don't appear in the app switcher) or the screen is being recorded or shared, and
/// the item locks again when the app goes to the background. The same covers the editor, whichever step is showing.
@MainActor
struct RecoveryPhraseDetailView: View {
    @State private var viewModel: RecoveryPhraseDetailViewModel
    @Binding private var navigationPath: NavigationPath

    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isSceneCaptured) private var isSceneCaptured
    @State private var currentError: (any Error)?
    @State private var isShowingDeleteConfirmation = false
    @State private var isSeedPassphraseRevealed = false

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
    }

    var body: some View {
        VaultItemDetailView(
            viewModel: viewModel,
            currentError: $currentError,
            isShowingDeleteConfirmation: $isShowingDeleteConfirmation,
            navigationPath: $navigationPath,
            presentationMode: presentationMode,
            editorKind: .recoveryPhrase,
            editorIdentity: identity,
            hiddenNotice: isContentHidden ? hiddenNotice : nil,
        ) {
            if viewModel.editingModel.detail.contents.isNotBlank {
                // Encrypted with the words, so it's as private as they are.
                DetailPageDescriptionSection(title: "Description", text: viewModel.editingModel.detail.contents)
                    .privacySensitive()
            }
            wordsSection
            if viewModel.editingModel.detail.seedPassphrase.isNotEmpty {
                seedPassphraseSection
            }
            DetailPageInfoSections(
                tags: viewModel.tagsThatAreSelected,
                entries: viewModel.detailEntries,
            )
        } editorStep: { step in
            editorStep(step)
        }
        .animation(.snappy, value: isContentHidden)
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
    }

    /// The words are sensitive enough that they shouldn't be visible in the app switcher, a screen recording or a
    /// mirrored screen.
    private var isContentHidden: Bool {
        scenePhase != .active || isSceneCaptured
    }

    private var hiddenNotice: VaultItemHiddenNotice {
        .init(
            title: "Hidden",
            subtitle: "Recovery phrases are hidden while Vault isn't in the foreground, or while the screen is being recorded or shared.",
        )
    }

    private var identity: DetailEditorItemIdentity {
        DetailEditorItemIdentity(
            systemImage: "list.number",
            title: viewModel.visibleTitle,
            subtitle: viewModel.editorSummary(for: .content),
            color: viewModel.editingModel.detail.color,
        )
    }

    @ViewBuilder
    private func editorStep(_ step: DetailEditorStep) -> some View {
        switch step {
        case .content:
            RecoveryPhraseWordsStep(viewModel: viewModel, isSeedPassphraseRevealed: $isSeedPassphraseRevealed)
        case .details:
            RecoveryPhraseNameStep(viewModel: viewModel)
        case .appearance:
            DetailEditorAppearanceStep(
                identity: identity,
                color: $viewModel.editingModel.detail.color,
                selectedTags: viewModel.tagsThatAreSelected,
                remainingTags: viewModel.remainingTags,
                tagCountDescription: viewModel.strings.tagCount(tags: viewModel.editingModel.detail.tags.count),
                addTag: { viewModel.editingModel.detail.tags.insert($0.id) },
                removeTag: { viewModel.editingModel.detail.tags.remove($0.id) },
            )
        case .security:
            RecoveryPhraseSecurityStep(viewModel: viewModel)
        }
    }

    // MARK: - Viewing

    /// The words, headed by whether they make a valid phrase: a card with its icon in the validation's color.
    private var wordsSection: some View {
        let summary = viewModel.validationSummary()
        return Section {
            DetailPageCardLabel(
                title: summary.title,
                subtitle: summary.detail,
                systemImage: summary.systemIconName,
                tint: validationColor(summary.kind),
            )
            .accessibilityElement(children: .combine)
            // The words go with their heading.
            .listRowSeparator(.hidden)

            RecoveryPhraseWordGridView(
                words: viewModel.editingModel.detail.words,
                isRevealed: viewModel.areWordsRevealed,
                highlightedPositions: summary.unknownWordPositions,
                wordNumberLabel: viewModel.strings.wordNumber,
                toggleRevealed: {
                    withAnimation(.snappy) {
                        viewModel.areWordsRevealed.toggle()
                    }
                },
            )
            .privacySensitive()
            .listRowInsets(EdgeInsets(vertical: 12, horizontal: 12))
        } footer: {
            Text(viewModel.areWordsRevealed ? "Tap a word to hide them all." : "Tap a word to reveal them all.")
        }
    }

    private func validationColor(_ kind: RecoveryPhraseValidationSummary.Kind) -> Color {
        switch kind {
        case .valid: .green
        case .warning: .orange
        case .neutral: .gray
        }
    }

    private var seedPassphraseSection: some View {
        Section {
            DetailPageCardLabel(title: "Passphrase", systemImage: "key.fill") {
                HStack(alignment: .firstTextBaseline) {
                    Group {
                        if isSeedPassphraseRevealed {
                            Text(verbatim: viewModel.editingModel.detail.seedPassphrase)
                        } else {
                            Text(verbatim: String(repeating: "•", count: 8))
                                .accessibilityLabel(Text("Hidden"))
                        }
                    }
                    .font(.body.monospaced())
                    .foregroundStyle(Color(uiColor: .label))
                    .privacySensitive()
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        isSeedPassphraseRevealed.toggle()
                    } label: {
                        Image(systemName: isSeedPassphraseRevealed ? "eye.slash" : "eye")
                            .accessibilityLabel(Text(isSeedPassphraseRevealed ? "Hide Passphrase" : "Show Passphrase"))
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }
}

/// Explains why a recovery phrase can't be created on a device without a passcode.
///
/// Shown in the new-item sheet in place of a recovery phrase's first step, so it sits on the sheet's glass like the
/// steps do.
struct RecoveryPhrasePasscodeRequiredView: View {
    @Environment(\.dismiss) private var dismiss
    /// Back to choosing another kind of item, when this is in the new-item sheet.
    @Environment(\.goBackFromFirstEditorStep) private var goBack

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
            .listRowBackground(DetailEditorRowBackground())
        }
        .environment(\.isInGuidedDetailEditor, true)
        .scrollContentBackground(.hidden)
        .reportsFittedSheetHeight()
        .navigationTitle("Recovery Phrase")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if let goBack {
                    Button {
                        goBack()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                } else {
                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel")
                    }
                }
            }
        }
    }
}
