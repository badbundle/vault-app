import MarkdownUI
import SwiftUI
import VaultFeed

@MainActor
struct SecureNoteDetailView: View {
    @State private var viewModel: SecureNoteDetailViewModel
    @Binding private var navigationPath: NavigationPath

    @Environment(\.presentationMode) private var presentationMode
    @State private var currentError: (any Error)?
    @State private var isShowingDeleteConfirmation = false

    init(
        editingExistingNote note: SecureNote,
        encryptionKey: DerivedEncryptionKey?,
        navigationPath: Binding<NavigationPath>,
        dataModel: VaultDataModel,
        storedMetadata: VaultItem.Metadata,
        editor: any SecureNoteDetailEditor,
        openInEditMode: Bool,
    ) {
        self.init(
            viewModel: .init(
                mode: .editing(note: note, metadata: storedMetadata, existingKey: encryptionKey),
                dataModel: dataModel,
                editor: editor,
            ),
            navigationPath: navigationPath,
        )
        if openInEditMode {
            viewModel.startEditing()
        }
    }

    /// A new note, locked as `newItemDefaults` say.
    init(
        newNoteWithEditor editor: any SecureNoteDetailEditor,
        navigationPath: Binding<NavigationPath>,
        dataModel: VaultDataModel,
        newItemDefaults: NewItemDefaults,
    ) {
        self.init(
            viewModel: .init(mode: .creating(defaults: newItemDefaults), dataModel: dataModel, editor: editor),
            navigationPath: navigationPath,
        )
        viewModel.startEditing()
    }

    init(viewModel: SecureNoteDetailViewModel, navigationPath: Binding<NavigationPath>) {
        _viewModel = .init(initialValue: viewModel)
        _navigationPath = navigationPath
    }

    var body: some View {
        GeometryReader { reader in
            VaultItemDetailView(
                viewModel: viewModel,
                currentError: $currentError,
                isShowingDeleteConfirmation: $isShowingDeleteConfirmation,
                navigationPath: $navigationPath,
                presentationMode: presentationMode,
                editorKind: .note,
                editorIdentity: identity,
            ) {
                noteContentsSection(size: reader.size)
                MetadataDisclosureSection(
                    tags: viewModel.tagsThatAreSelected,
                    entries: viewModel.detailEntries,
                )
            } editorStep: { step in
                editorStep(step)
            }
        }
        // Viewing, the note fills the screen whether or not the keyboard is up. Editing, the keyboard has to push
        // the text up, so what's being typed stays in view.
        .ignoresSafeArea(viewModel.isInEditMode ? [] : .keyboard)
    }

    private var noteSymbol: String {
        viewModel.editingModel.detail.lockState.isLocked ? "lock.doc.fill" : "doc.text.fill"
    }

    private var identity: DetailEditorItemIdentity {
        let detail = viewModel.editingModel.detail
        return DetailEditorItemIdentity(
            systemImage: noteSymbol,
            title: detail.titleLine.isNotBlank ? detail.titleLine : viewModel.strings.noteEmptyTitleTitle,
            subtitle: detail.textFormat.localizedString,
            color: detail.color,
        )
    }

    @ViewBuilder
    private func editorStep(_ step: DetailEditorStep) -> some View {
        switch step {
        case .content:
            SecureNoteContentStep(viewModel: viewModel)
        case .details:
            // Not one of a note's steps: its first line is its title.
            EmptyView()
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
            SecureNoteSecurityStep(viewModel: viewModel)
        }
    }

    // MARK: - Viewing

    private func noteContentsSection(size: CGSize) -> some View {
        Section {
            switch viewModel.editingModel.detail.textFormat {
            case .plain:
                SelectableText(
                    viewModel.editingModel.detail.contents,
                    fontStyle: .monospace,
                    textStyle: .subheadline,
                )
                .frame(minHeight: size.height - 100, alignment: .top)
                .listRowInsets(EdgeInsets())
            case .markdown:
                Markdown(.init(viewModel.editingModel.detail.contents))
                    .textSelection(.enabled)
                    .frame(minHeight: size.height - 100, alignment: .top)
                    .listRowInsets(EdgeInsets(vertical: 12, horizontal: 16))
            }
        } header: {
            Image(systemName: noteSymbol)
                .font(.title)
                .foregroundStyle((viewModel.editingModel.detail.color ?? .default).color)
                .containerRelativeFrame(.horizontal)
                .padding(.vertical, 2)
        }
    }
}

#Preview("Viewing") {
    SecureNoteDetailView(
        editingExistingNote: .init(
            title: "Hello",
            contents: "This is the contents, it is long \n\n## Nice title",
            format: .markdown,
        ),
        encryptionKey: nil,
        navigationPath: .constant(.init()),
        dataModel: .init(
            vaultStore: VaultStoreStub(),
            vaultTagStore: VaultTagStoreStub(),
            vaultImporter: VaultStoreImporterMock(),
            vaultDeleter: VaultStoreDeleterMock(),
            vaultKillphraseDeleter: VaultStoreKillphraseDeleterMock(),
            vaultOtpAutofillStore: VaultOTPAutofillStoreMock(),
            backupPasswordStore: BackupPasswordStoreMock(),
            killphraseKeyStore: KillphraseKeyStoreMock(),
            killphraseRehashService: nil,
            searchPassphraseKeyStore: SearchPassphraseKeyStoreMock(),
            searchPassphraseRehashService: nil,
            backupEventLogger: BackupEventLoggerMock(),
        ),
        storedMetadata: .init(
            id: .init(),
            created: .init(),
            updated: .init(),
            relativeOrder: 0,
            userDescription: "testing",
            tags: [],
            visibility: .always,
            searchableLevel: .full,
            searchPassphrase: nil,
            killphrase: nil,
            lockState: .notLocked,
            color: nil,
            showInQuickType: false,
            previewMode: .titleAndFirstLine,
        ),
        editor: SecureNoteDetailEditorMock(),
        openInEditMode: false,
    )
    .environment(DeviceAuthenticationService(policy: .alwaysAllow))
}

#Preview("Editing") {
    SecureNoteDetailView(
        newNoteWithEditor: SecureNoteDetailEditorMock(),
        navigationPath: .init(projectedValue: .constant(.init())),
        dataModel: .init(
            vaultStore: VaultStoreStub(),
            vaultTagStore: VaultTagStoreStub(),
            vaultImporter: VaultStoreImporterMock(),
            vaultDeleter: VaultStoreDeleterMock(),
            vaultKillphraseDeleter: VaultStoreKillphraseDeleterMock(),
            vaultOtpAutofillStore: VaultOTPAutofillStoreMock(),
            backupPasswordStore: BackupPasswordStoreMock(),
            killphraseKeyStore: KillphraseKeyStoreMock(),
            killphraseRehashService: nil,
            searchPassphraseKeyStore: SearchPassphraseKeyStoreMock(),
            searchPassphraseRehashService: nil,
            backupEventLogger: BackupEventLoggerMock(),
        ),
        newItemDefaults: NewItemDefaults(),
    )
    .environment(DeviceAuthenticationService(policy: .alwaysAllow))
}
