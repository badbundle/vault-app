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
    @State private var currentError: (any Error)?
    @State private var isShowingDeleteConfirmation = false

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
        self.init(
            viewModel: .init(
                mode: .editing(code: code, metadata: storedMetadata),
                dataModel: dataModel,
                editor: editor,
            ),
            navigationPath: navigationPath,
            previewGenerator: previewGenerator,
            copyActionHandler: copyActionHandler,
            presentationMode: presentationMode,
        )
        if openInEditMode {
            viewModel.startEditing()
        }
    }

    /// A new code, starting from scanning or entering its key.
    init(
        newCodeWithEditor editor: any OTPCodeDetailEditor,
        navigationPath: Binding<NavigationPath>,
        dataModel: VaultDataModel,
        previewGenerator: PreviewGenerator,
        copyActionHandler: any VaultItemCopyActionHandler,
        presentationMode: Binding<PresentationMode>?,
    ) {
        self.init(
            viewModel: .init(mode: .creating(), dataModel: dataModel, editor: editor),
            navigationPath: navigationPath,
            previewGenerator: previewGenerator,
            copyActionHandler: copyActionHandler,
            presentationMode: presentationMode,
        )
        viewModel.startEditing()
    }

    init(
        viewModel: OTPCodeDetailViewModel,
        navigationPath: Binding<NavigationPath>,
        previewGenerator: PreviewGenerator,
        copyActionHandler: any VaultItemCopyActionHandler,
        presentationMode: Binding<PresentationMode>?,
    ) {
        _viewModel = .init(initialValue: viewModel)
        _navigationPath = navigationPath
        self.previewGenerator = previewGenerator
        self.copyActionHandler = copyActionHandler
        self.presentationMode = presentationMode
    }

    var body: some View {
        VaultItemDetailView(
            viewModel: viewModel,
            currentError: $currentError,
            isShowingDeleteConfirmation: $isShowingDeleteConfirmation,
            navigationPath: $navigationPath,
            presentationMode: presentationMode,
            editorKind: .code,
            editorIdentity: identity,
        ) {
            if case let .editing(code, metadata) = viewModel.mode {
                codeInformationSection(code: code, metadata: metadata)
                descriptionSection
                MetadataDisclosureSection(
                    tags: viewModel.tagsThatAreSelected,
                    entries: viewModel.detailMenuItems,
                )
            }
        } editorStep: { step in
            editorStep(step)
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

    private var identity: DetailEditorItemIdentity {
        let detail = viewModel.editingModel.detail
        return DetailEditorItemIdentity(
            systemImage: "key.horizontal.fill",
            title: viewModel.visibleIssuerTitle,
            subtitle: detail.accountNameTitle,
            color: detail.color,
        )
    }

    @ViewBuilder
    private func editorStep(_ step: DetailEditorStep) -> some View {
        switch step {
        case .content:
            OTPCodeKeyStep(viewModel: viewModel)
        case .details:
            OTPCodeNameStep(viewModel: viewModel)
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
            OTPCodeSecurityStep(viewModel: viewModel)
        }
    }

    private func codeInformationSection(code: OTPAuthCode, metadata: VaultItem.Metadata) -> some View {
        Section {} header: {
            copyableViewGenerator().makeVaultPreviewView(
                item: .otpCode(code),
                metadata: metadata,
                behaviour: .normal,
            )
            .frame(maxWidth: 240)
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
