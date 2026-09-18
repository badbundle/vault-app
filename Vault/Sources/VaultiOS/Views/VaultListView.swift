import Combine
import SwiftUI
import VaultFeed
import VaultSettings

@MainActor
struct VaultListView<
    Generator: VaultItemPreviewViewGenerator<VaultItem.Payload>,
>: View {
    var localSettings: LocalSettings
    var viewGenerator: Generator
    var copyActionHandler: any VaultItemCopyActionHandler
    var previewActionHandler: any VaultItemPreviewActionHandler
    @Binding var pendingOpenItemDetail: Identifier<VaultItem>?
    let openDetailSubject = PassthroughSubject<VaultItemEncryptionPayload, Never>()

    init(
        localSettings: LocalSettings,
        viewGenerator: Generator,
        copyActionHandler: any VaultItemCopyActionHandler,
        previewActionHandler: any VaultItemPreviewActionHandler,
        pendingOpenItemDetail: Binding<Identifier<VaultItem>?> = .constant(nil),
    ) {
        self.localSettings = localSettings
        self.viewGenerator = viewGenerator
        self.copyActionHandler = copyActionHandler
        self.previewActionHandler = previewActionHandler
        _pendingOpenItemDetail = pendingOpenItemDetail
    }

    @Environment(VaultDataModel.self) private var dataModel
    @Environment(Pasteboard.self) var pasteboard: Pasteboard
    @Environment(DeviceAuthenticationService.self) var authenticationService
    @State private var vaultItemFeedState = VaultItemFeedState()
    @State private var modal: Modal?
    @State private var navigationPath = NavigationPath()
    @Environment(\.scenePhase) private var scenePhase

    enum Modal: Hashable, IdentifiableSelf {
        case detail(Identifier<VaultItem>, VaultItem, DerivedEncryptionKey?)
        case creatingItem(CreatingItem)
    }

    var body: some View {
        VaultItemFeedView(
            localSettings: localSettings,
            viewGenerator: interactableViewGenerator(),
            state: vaultItemFeedState,
            gridSpacing: 12,
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        modal = .creatingItem(.otpCode)
                    } label: {
                        LabeledContent {
                            Text("Code")
                        } label: {
                            Image(systemName: "qrcode")
                        }
                    }

                    Button {
                        modal = .creatingItem(.secureNote)
                    } label: {
                        LabeledContent {
                            Text("Note")
                        } label: {
                            Image(systemName: "text.alignleft")
                        }
                    }
                } label: {
                    Label("Add Item", systemImage: "plus")
                }
            }
        }
        .sheet(item: $modal, onDismiss: nil) { visible in
            switch visible {
            case let .detail(_, storedCode, encryptionKey):
                NavigationStack(path: $navigationPath) {
                    VaultDetailEditView(
                        storedItem: storedCode,
                        previewGenerator: viewGenerator,
                        copyActionHandler: copyActionHandler,
                        openInEditMode: vaultItemFeedState.isEditing,
                        openDetailSubject: openDetailSubject,
                        encryptionKey: encryptionKey,
                        navigationPath: $navigationPath,
                    )
                }
            case let .creatingItem(creatingItem):
                NavigationStack(path: $navigationPath) {
                    VaultDetailCreateView(
                        creatingItem: creatingItem,
                        previewGenerator: viewGenerator,
                        copyActionHandler: copyActionHandler,
                        navigationPath: $navigationPath,
                    )
                }
            }
        }
        .onReceive(openDetailSubject, perform: { vaultItemEncryptedPayload in
            let item = vaultItemEncryptedPayload.decryptedItem
            modal = .detail(item.id, item, vaultItemEncryptedPayload.encryptionKey)
        })
        .onChange(of: modal) { _, newValue in
            // When the detail modal is dismissed, exit editing mode.
            if newValue == nil {
                vaultItemFeedState.isEditing = false
            }
        }
        .onChange(of: scenePhase) { _, newValue in
            viewGenerator.scenePhaseDidChange(to: newValue)
        }
        .onAppear {
            viewGenerator.didAppear()
            openPendingItemDetailIfPossible()
        }
        .onChange(of: pendingOpenItemDetail) { _, _ in
            openPendingItemDetailIfPossible()
        }
        .onChange(of: dataModel.items.map(\.id)) { _, _ in
            openPendingItemDetailIfPossible()
        }
    }

    func interactableViewGenerator()
        -> VaultItemOnTapDecoratorViewGenerator<Generator>
    {
        VaultItemOnTapDecoratorViewGenerator(generator: viewGenerator) { id in
            if vaultItemFeedState.isEditing {
                guard let item = dataModel.code(id: id) else { return }
                modal = .detail(id, item, nil)
            } else if let previewAction = previewActionHandler.previewActionForVaultItem(id: id) {
                switch previewAction {
                case let .copyText(copyAction):
                    if copyAction.requiresAuthenticationToCopy {
                        let result = try await authenticationService
                            .authenticate(reason: "Authenticate to copy locked data")
                        guard result == .success(.authenticated) else { return }
                    }
                    pasteboard.copy(copyAction)
                case let .openItemDetail(id):
                    guard let item = dataModel.code(id: id) else { return }
                    modal = .detail(id, item, nil)
                }
            }
        }
    }

    private func openPendingItemDetailIfPossible() {
        guard let id = pendingOpenItemDetail,
              let item = dataModel.code(id: id)
        else { return }

        pendingOpenItemDetail = nil
        modal = .detail(id, item, nil)
    }
}
