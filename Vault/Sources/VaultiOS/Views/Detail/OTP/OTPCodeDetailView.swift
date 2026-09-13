import SwiftUI
import VaultFeed

@MainActor
struct OTPCodeDetailView<PreviewGenerator: VaultItemPreviewViewGenerator<VaultItem.Payload>>: View {
    @State private var viewModel: OTPCodeDetailViewModel
    private var previewGenerator: PreviewGenerator
    private var copyActionHandler: any VaultItemCopyActionHandler
    @Binding var navigationPath: NavigationPath
    private var presentationMode: Binding<PresentationMode>?

    @Environment(Pasteboard.self) private var pasteboard: Pasteboard
    @Environment(DeviceAuthenticationService.self) private var authenticationService
    @State private var selectedColor: Color
    @State private var currentError: (any Error)?
    @State private var isShowingDeleteConfirmation = false
    @State private var modal: Modal?

    private enum Modal: IdentifiableSelf {
        case editLock
        case editPassphrase
        case editKillphrase
        case editTags
    }

    init(
        editingExistingCode code: OTPAuthCode,
        navigationPath: Binding<NavigationPath>,
        dataModel: VaultDataModel,
        storedMetadata: VaultItem.Metadata,
        editor: any OTPCodeDetailEditor,
        previewGenerator: PreviewGenerator,
        copyActionHandler: any VaultItemCopyActionHandler,
        openInEditMode: Bool,
        presentationMode: Binding<PresentationMode>?,
    ) {
        _navigationPath = navigationPath
        _viewModel = .init(initialValue: .init(
            mode: .editing(code: code, metadata: storedMetadata),
            dataModel: dataModel,
            editor: editor,
        ))
        self.previewGenerator = previewGenerator
        self.copyActionHandler = copyActionHandler
        self.presentationMode = presentationMode
        _selectedColor = State(initialValue: storedMetadata.color?.color ?? VaultItemColor.default.color)

        if openInEditMode {
            viewModel.startEditing()
        }
    }

    init(
        newCodeWithContext initialCode: OTPAuthCode?,
        navigationPath: Binding<NavigationPath>,
        dataModel: VaultDataModel,
        editor: any OTPCodeDetailEditor,
        previewGenerator: PreviewGenerator,
        copyActionHandler: any VaultItemCopyActionHandler,
        presentationMode: Binding<PresentationMode>?,
    ) {
        _navigationPath = navigationPath
        _viewModel = .init(initialValue: .init(
            mode: .creating(initialCode: initialCode),
            dataModel: dataModel,
            editor: editor,
        ))
        self.previewGenerator = previewGenerator
        self.copyActionHandler = copyActionHandler
        self.presentationMode = presentationMode
        _selectedColor = .init(initialValue: VaultItemColor.default.color)

        viewModel.startEditing()
    }

    var body: some View {
        VaultItemDetailView(
            viewModel: viewModel,
            currentError: $currentError,
            isShowingDeleteConfirmation: $isShowingDeleteConfirmation,
            navigationPath: $navigationPath,
            presentationMode: presentationMode,
        ) {
            if viewModel.isInEditMode {
                if viewModel.showsKeyEditingFields {
                    keyEditingSection
                }
                nameEditingSection
                descriptionEditingSection
                editingActionsSection
            } else {
                if case let .editing(code, metadata) = viewModel.mode {
                    codeInformationSection(code: code, metadata: metadata)
                    descriptionSection
                    MetadataDisclosureSection(
                        tags: viewModel.tagsThatAreSelected,
                        entries: viewModel.detailMenuItems,
                    )
                }
            }
        }
        .animation(.easeOut, value: viewModel.editingModel.detail.viewConfig)
        .sheet(item: $modal, onDismiss: nil, content: { item in
            switch item {
            case .editLock:
                NavigationStack {
                    VaultDetailLockEditView(
                        title: "Lock",
                        description: "Locked codes require authentication to view or edit. You will need to authenticate every time before you can view or copy the code.",
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
                        description: "Codes that require a passphrase are hidden from the main feed. You need to search exactly for your chosen passphrase each time to view this code.",
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
                        description: "A killphrase is a secret phrase that is used to immediately delete this code. In the search bar, search exactly for this text and the code will be immediately and quitely deleted. Combined with a search passphrase, you can delete an item without it being made visible.",
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
        })
        .onChange(of: selectedColor.hashValue) { _, _ in
            viewModel.editingModel.detail.color = VaultItemColor(color: selectedColor)
        }
        .onDisappear {
            // Clear the state of the navigation path, if any.
            // This is because of a BUG where (when we use the injected presentationMode to dismiss the navigation
            // stack), launching the navigation stack the next time (to view another code) might have the detail
            // already presented!!!
            //
            // Some weird cache issue or something, but this fixes it.
            navigationPath.removeLast(navigationPath.count)
        }
    }

    private var iconHeader: some View {
        Image(systemName: "key.horizontal.fill")
            .font(.title)
            .foregroundStyle(selectedColor)
    }

    private var iconEditingHeader: some View {
        VStack(spacing: 6) {
            Image(systemName: "key.horizontal.fill")
                .font(.title)
                .foregroundStyle(selectedColor)

            ColorPicker(selection: $selectedColor, supportsOpacity: false, label: {
                EmptyView()
            })
            .labelsHidden()
        }
    }

    private var nameEditingSection: some View {
        Section {
            TextField(
                viewModel.strings.siteNameTitle,
                text: $viewModel.editingModel.detail.issuerTitle,
            )
            TextField(text: $viewModel.editingModel.detail.accountNameTitle) {
                Text(viewModel.strings.accountNameExample)
            }
        } header: {
            iconEditingHeader
                .containerRelativeFrame(.horizontal)
                .padding(.vertical, 2)
                .padding(.bottom, 4)
        }
    }

    private var descriptionEditingSection: some View {
        Section {
            TextEditor(text: $viewModel.editingModel.detail.description)
                .font(.subheadline)
                .frame(minHeight: 120)
                .keyboardType(.default)
                .listRowInsets(EdgeInsets())
        } header: {
            Text(viewModel.strings.descriptionTitle)
        }
    }

    private var keyEditingSection: some View {
        Section {
            TextField(viewModel.strings.inputSecretTitle, text: $viewModel.editingModel.detail.secretBase32String)

            Picker(selection: $viewModel.editingModel.detail.codeType) {
                ForEach(OTPAuthType.Kind.allCases) { authType in
                    Text(viewModel.strings.codeKindTitle(kind: authType))
                        .tag(authType)
                }
            } label: {
                Text(viewModel.strings.inputCodeTypeTitle)
            }

            DisclosureGroup {
                switch viewModel.editingModel.detail.codeType {
                case .totp:
                    Stepper(value: $viewModel.editingModel.detail.totpPeriodLength, in: 1 ... UInt64(Int.max)) {
                        LabeledContent(
                            viewModel.strings.inputTotpPeriodTitle,
                            value: "\(viewModel.editingModel.detail.totpPeriodLength)",
                        )
                    }
                case .hotp:
                    Stepper(value: $viewModel.editingModel.detail.hotpCounterValue, in: 0 ... UInt64(Int.max)) {
                        LabeledContent(
                            viewModel.strings.inputHotpCounterTitle,
                            value: "\(viewModel.editingModel.detail.hotpCounterValue)",
                        )
                    }
                }

                Picker(selection: $viewModel.editingModel.detail.algorithm) {
                    ForEach(OTPAuthAlgorithm.allCases) { algorithm in
                        Text(algorithm.stringValue)
                            .tag(algorithm)
                    }
                } label: {
                    Text(viewModel.strings.inputAlgorithmTitle)
                }

                Stepper(value: $viewModel.editingModel.detail.numberOfDigits, in: 1 ... UInt16.max) {
                    LabeledContent(
                        viewModel.strings.inputNumberOfDigitsTitle,
                        value: "\(viewModel.editingModel.detail.numberOfDigits)",
                    )
                }
            } label: {
                Text(viewModel.strings.advancedSectionTitle)
            }
        } header: {
            OTPKeyValidationView(
                validationState: viewModel.editingModel.detail.$secretBase32String,
                validTitle: viewModel.strings.inputKeyValidTitle,
                invalidTitle: viewModel.strings.inputKeyEmptyTitle,
                errorTitle: viewModel.strings.inputKeyErrorTitle,
            )
            .padding()
            .modifier(HorizontallyCenter())
        }
    }

    private func codeInformationSection(code: OTPAuthCode, metadata: VaultItem.Metadata) -> some View {
        Section {} header: {
            copyableViewGenerator().makeVaultPreviewView(
                item: .otpCode(code),
                metadata: metadata,
                behaviour: .normal,
            )
            .frame(width: 180)
            .fixedSize(horizontal: false, vertical: true)
            .containerRelativeFrame(.horizontal)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var descriptionSection: some View {
        if viewModel.editingModel.detail.description.isNotBlank {
            Section {
                Text(viewModel.editingModel.detail.description)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .font(.callout)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } header: {
                Text(viewModel.strings.descriptionTitle)
            }
        }
    }

    private var editingActionsSection: some View {
        Section {
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

            Toggle(isOn: $viewModel.editingModel.detail.showInQuickType) {
                FormRow(
                    image: Image(systemName: "keyboard"),
                    color: .accentColor,
                    style: .standard,
                ) {
                    Text("Show in QuickType")
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
        } footer: {
            if viewModel.shouldShowDeleteButton {
                deleteButton
                    .padding(.horizontal)
                    .modifier(HorizontallyCenter())
                    .padding(.vertical, 12)
            }
        }
    }

    private var deleteButton: some View {
        Button {
            isShowingDeleteConfirmation = true
        } label: {
            Label(localized(key: "action.delete.title"), systemImage: "trash.fill")
        }
        .modifier(ProminentButtonModifier(color: .red))
    }

    func copyableViewGenerator() -> VaultItemOnTapDecoratorViewGenerator<PreviewGenerator> {
        VaultItemOnTapDecoratorViewGenerator(generator: previewGenerator) { id in
            if let copyAction = copyActionHandler.textToCopyForVaultItem(id: id) {
                if copyAction.requiresAuthenticationToCopy {
                    let result = try await authenticationService.authenticate(reason: "Copy locked text")
                    guard result == .success(.authenticated) else { return }
                }
                pasteboard.copy(copyAction)
            }
        }
    }
}

#Preview {
    OTPCodeDetailView(
        editingExistingCode: .init(
            type: .totp(),
            data: .init(secret: .empty(), accountName: "Test"),
        ),
        navigationPath: .constant(.init()),
        dataModel: VaultDataModel(
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
            id: .new(),
            created: Date(),
            updated: Date(),
            relativeOrder: .min,
            userDescription: "Description",
            tags: [],
            visibility: .always,
            searchableLevel: .full,
            searchPassphrase: nil,
            killphrase: nil,
            lockState: .notLocked,
            color: VaultItemColor(color: .green),
            showInQuickType: true,
            previewMode: .titleAndFirstLine,
        ),
        editor: OTPCodeDetailEditorMock(),
        previewGenerator: VaultItemPreviewViewGeneratorMock(),
        copyActionHandler: VaultItemCopyActionHandlerMock(),
        openInEditMode: false,
        presentationMode: nil,
    )
    .environment(Pasteboard(
        SystemPasteboardImpl(clock: EpochClockImpl()),
        localSettings: .init(defaults: .init(userDefaults: .standard)),
    ))
}
