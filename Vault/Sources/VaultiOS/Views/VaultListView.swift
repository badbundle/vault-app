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
        case choosingItemType
        case creatingItem(CreatingItem)
    }

    var body: some View {
        VaultItemFeedView(
            localSettings: localSettings,
            viewGenerator: interactableViewGenerator(),
            state: vaultItemFeedState,
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    modal = .choosingItemType
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
            case .choosingItemType:
                // A `Modal` case rather than its own `.sheet`: presenting
                // the create flow from the picker's `onDismiss` is dropped
                // by SwiftUI often enough to be unusable, whereas changing
                // the item lets it sequence the dismiss and present itself.
                CreateItemPickerView { creatingItem in
                    modal = .creatingItem(creatingItem)
                }
            case let .creatingItem(creatingItem):
                // The editor sizes the sheet to each step. Every view shown
                // here sets its detents, because this sheet follows the
                // picker: without them the picker's fitted detent leaks into
                // this presentation and a tap on the sheet's empty space
                // dismisses it.
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
        -> VaultItemMenuDecoratorViewGenerator<VaultItemOnTapDecoratorViewGenerator<Generator>>
    {
        let tapHandler = tapHandler
        let tappable = VaultItemOnTapDecoratorViewGenerator(generator: viewGenerator) { id in
            try await tapHandler.tap(
                id,
                isEditing: vaultItemFeedState.isEditing,
                codeTapAction: localSettings.state.codeTapAction,
            )
        }
        return VaultItemMenuDecoratorViewGenerator(generator: tappable) { id, behaviour in
            tapHandler.menuActions(for: id, isEditing: behaviour != .normal)
        } perform: { action, id in
            try await tapHandler.perform(action, on: id)
        }
    }

    private var tapHandler: VaultItemTapHandler {
        VaultItemTapHandler(
            previewActionHandler: previewActionHandler,
            authenticationService: authenticationService,
            copy: { pasteboard.copy($0) },
            showDetails: { id in
                guard let item = dataModel.code(id: id) else { return }
                modal = .detail(id, item, nil)
            },
        )
    }

    private func openPendingItemDetailIfPossible() {
        guard let id = pendingOpenItemDetail,
              let item = dataModel.code(id: id)
        else { return }

        pendingOpenItemDetail = nil
        modal = .detail(id, item, nil)
    }
}
