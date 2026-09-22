import MarkdownUI
import SwiftUI
import VaultFeed

@MainActor
struct SecureNoteDetailView: View {
    @State private var viewModel: SecureNoteDetailViewModel
    @Binding private var navigationPath: NavigationPath

    @Environment(\.presentationMode) private var presentationMode
    @State private var selectedColor: Color
    @State private var modal: Modal?

    private enum Modal: IdentifiableSelf {
        case editLock
        case editPassphrase
        case editKillphrase
        case editEncryption
        case editPreviewMode
        case editTags
    }

    init(
        editingExistingNote note: SecureNote,
        encryptionKey: DerivedEncryptionKey?,
        navigationPath: Binding<NavigationPath>,
        dataModel: VaultDataModel,
        storedMetadata: VaultItem.Metadata,
        editor: any SecureNoteDetailEditor,
        openInEditMode: Bool,
    ) {
        _navigationPath = navigationPath
        _viewModel = .init(initialValue: .init(
            mode: .editing(note: note, metadata: storedMetadata, existingKey: encryptionKey),
            dataModel: dataModel,
            editor: editor,
        ))
        _selectedColor = State(initialValue: storedMetadata.color?.color ?? VaultItemColor.default.color)

        if openInEditMode {
            viewModel.startEditing()
        }
    }

    init(
        newNoteWithEditor editor: any SecureNoteDetailEditor,
        navigationPath: Binding<NavigationPath>,
        dataModel: VaultDataModel,
    ) {
        _navigationPath = navigationPath
        _viewModel = .init(initialValue: .init(
            mode: .creating,
            dataModel: dataModel,
            editor: editor,
        ))
        _selectedColor = .init(initialValue: VaultItemColor.default.color)

        viewModel.startEditing()
    }

    @State private var currentError: (any Error)?
    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        GeometryReader { reader in
            VaultItemDetailView(
                viewModel: viewModel,
                currentError: $currentError,
                isShowingDeleteConfirmation: $isShowingDeleteConfirmation,
                navigationPath: $navigationPath,
                presentationMode: presentationMode,
            ) {
                if viewModel.isInEditMode {
                    noteContentsEditingSection
                    editingActionsSection
                } else {
                    noteContentsSection(size: reader.size)
                    MetadataDisclosureSection(
                        tags: viewModel.tagsThatAreSelected,
                        entries: viewModel.detailEntries,
                    )
                }
            }
        }
        .ignoresSafeArea(.keyboard)
        .animation(.snappy, value: viewModel.editingModel.detail.viewConfig)
        .onChange(of: selectedColor.hashValue) { _, _ in
            viewModel.editingModel.detail.color = VaultItemColor(color: selectedColor)
        }
        .sheet(item: $modal, onDismiss: nil) { item in
            switch item {
            case .editLock:
                NavigationStack {
                    VaultDetailLockEditView(
                        title: "Lock",
                        description: "Locked notes require authentication to view or edit. The title and first line of the note will be visible in the preview.",
                        lockState: $viewModel.editingModel.detail.lockState,
                    )
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button {
                                modal = nil
                            } label: {
                                Text("Done")
                            }
                        }
                    }
                }
            case .editPassphrase:
                NavigationStack {
                    VaultDetailPassphraseEditView(
                        title: "Visibility",
                        description: "Notes that require a passphrase are hidden from the main feed. You need to search exactly for your chosen passphrase each time to view this note.",
                        hiddenWithPassphraseTitle: viewModel.strings.passphraseSubtitle,
                        viewConfig: $viewModel.editingModel.detail.viewConfig,
                        passphrase: $viewModel.editingModel.detail.searchPassphrase,
                    )
                    .interactiveDismissDisabled(!viewModel.editingModel.detail.isPassphraseValid)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button {
                                modal = nil
                            } label: {
                                Text("Done")
                            }
                            .disabled(!viewModel.editingModel.detail.isPassphraseValid)
                        }
                    }
                }
            case .editKillphrase:
                NavigationStack {
                    VaultDetailKillphraseEditView(
                        title: "Killphrase",
                        description: "A killphrase is a secret phrase that is used to immediately delete this note. In the search bar, search exactly for this text and the note will be immediately and quitely deleted. Combined with a search passphrase, you can delete an item without it being made visible.",
                        hiddenWithKillphraseTitle: viewModel.strings.killphraseSubtitle,
                        killphraseEnabled: $viewModel.editingModel.detail.killphraseEnabled,
                        newKillphrase: $viewModel.editingModel.detail.newKillphrase,
                    )
                    .interactiveDismissDisabled(!viewModel.editingModel.detail.isKillphraseValid)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button {
                                modal = nil
                            } label: {
                                Text("Done")
                            }
                            .disabled(!viewModel.editingModel.detail.isKillphraseValid)
                        }
                    }
                }
            case .editEncryption:
                NavigationStack {
                    VaultDetailEncryptionEditView(
                        title: "Encryption",
                        description: "Locks this note cryptographically on your device. Password is required on every view.",
                        encryptionInitiallyEnabled: viewModel.editingModel.detail.encrypted,
                        didSetNewEncryptionPassword: { newPassword in
                            viewModel.editingModel.detail.newEncryptionPassword = newPassword
                        },
                        didRemoveEncryption: {
                            viewModel.editingModel.detail.newEncryptionPassword = ""
                            viewModel.editingModel.detail.existingEncryptionKey = nil
                        },
                    )
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button {
                                modal = nil
                            } label: {
                                Text("Done")
                            }
                        }
                    }
                }
            case .editPreviewMode:
                NavigationStack {
                    VaultDetailNotePreviewEditView(
                        title: "Preview",
                        description: "Controls what appears in the note's preview tile. Hiding fields keeps content off the main feed.",
                        isEncrypted: viewModel.editingModel.detail.encrypted,
                        previewMode: $viewModel.editingModel.detail.previewMode,
                    )
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button {
                                modal = nil
                            } label: {
                                Text("Done")
                            }
                        }
                    }
                }
            case .editTags:
                NavigationStack {
                    VaultDetailTagEditView(
                        tagsThatAreSelected: viewModel.tagsThatAreSelected,
                        remainingTags: viewModel.remainingTags,
                        didAdd: { viewModel.editingModel.detail.tags.insert($0.id) },
                        didRemove: { viewModel.editingModel.detail.tags.remove($0.id) },
                    )
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button {
                                modal = nil
                            } label: {
                                Text("Done")
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Title

    private var noteIconHeader: some View {
        Image(systemName: viewModel.editingModel.detail.lockState.isLocked ? "lock.doc.fill" : "doc.text.fill")
            .font(.title)
            .foregroundStyle(selectedColor)
    }

    private var noteIconEditingHeader: some View {
        VStack(spacing: 6) {
            Image(systemName: viewModel.editingModel.detail.lockState.isLocked ? "lock.doc.fill" : "doc.text.fill")
                .font(.title)
                .foregroundStyle(selectedColor)

            ColorPicker(selection: $selectedColor, supportsOpacity: false, label: {
                EmptyView()
            })
            .labelsHidden()
        }
    }

    // MARK: Contents

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
            noteIconHeader
                .containerRelativeFrame(.horizontal)
                .padding(.vertical, 2)
        }
    }

    private var noteContentsEditingSection: some View {
        Section {
            TextEditor(text: $viewModel.editingModel.detail.contents)
                .font(.subheadline)
                .fontDesign(.monospaced)
                .frame(minHeight: 400)
                .keyboardType(.default)
                .contentMargins(12, for: .scrollContent)
                .listRowInsets(EdgeInsets())
        } header: {
            noteIconEditingHeader
                .containerRelativeFrame(.horizontal)
                .padding(.vertical, 2)
                .padding(.bottom, 4)
        }
    }

    @ViewBuilder
    private var editingActionsSection: some View {
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

            Button {
                modal = .editPassphrase
            } label: {
                FormRow(
                    image: Image(systemName: viewModel.editingModel.detail.viewConfig.systemIconName),
                    color: .accentColor,
                    style: .standard,
                ) {
                    LabeledContent("Visibility", value: viewModel.editingModel.detail.viewConfig.localizedTitle)
                        .font(.body)
                }
            }

            Button {
                modal = .editPreviewMode
            } label: {
                FormRow(
                    image: Image(systemName: "rectangle.dashed"),
                    color: .accentColor,
                    style: .standard,
                ) {
                    LabeledContent("Preview", value: viewModel.editingModel.detail.previewMode.localizedTitle)
                        .font(.body)
                }
            }

            Button {
                modal = .editLock
            } label: {
                FormRow(
                    image: Image(systemName: viewModel.editingModel.detail.lockState.systemIconName),
                    color: .accentColor,
                    style: .standard,
                ) {
                    LabeledContent("Lock", value: viewModel.editingModel.detail.lockState.localizedTitle)
                        .font(.body)
                }
            }

            Button {
                modal = .editKillphrase
            } label: {
                FormRow(
                    image: Image(systemName: viewModel.editingModel.detail.killphraseEnabledIcon),
                    color: .accentColor,
                    style: .standard,
                ) {
                    LabeledContent("Killphrase", value: viewModel.editingModel.detail.killphraseEnabledText)
                        .font(.body)
                }
            }

            Button {
                modal = .editEncryption
            } label: {
                FormRow(
                    image: Image(systemName: "lock.iphone"),
                    color: .accentColor,
                    style: .standard,
                ) {
                    LabeledContent("Encryption", value: viewModel.editingModel.detail.encryptionEnabledText)
                        .font(.body)
                }
            }

            Button {
                modal = .editTags
            } label: {
                VStack {
                    FormRow(
                        image: Image(systemName: "tag"),
                        color: .accentColor,
                        style: .standard,
                    ) {
                        LabeledContent(
                            "Tags",
                            value: viewModel.strings.tagCount(tags: viewModel.editingModel.detail.tags.count),
                        )
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
        }

        if viewModel.shouldShowDeleteButton {
            Section {
                deleteButton
            }
        }
    }

    private var deleteButton: some View {
        ProminentActionButton(localized(key: "action.delete.title"), systemImage: "trash.fill", role: .destructive) {
            isShowingDeleteConfirmation = true
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
    )
    .environment(DeviceAuthenticationService(policy: .alwaysAllow))
}
