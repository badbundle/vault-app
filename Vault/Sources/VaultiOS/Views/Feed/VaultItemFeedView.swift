import CryptoEngine
import SwiftUI
import VaultFeed
import VaultSettings

@MainActor
public struct VaultItemFeedView<
    ViewGenerator: VaultItemPreviewViewGenerator,
>: View where
    ViewGenerator.PreviewItem == VaultItem.Payload
{
    var localSettings: LocalSettings
    var viewGenerator: ViewGenerator
    var gridSpacing: Double

    @Environment(VaultInjector.self) private var injector
    @Environment(VaultDataModel.self) private var dataModel
    @State private var state: VaultItemFeedState

    public init(
        localSettings: LocalSettings,
        viewGenerator: ViewGenerator,
        state: VaultItemFeedState,
        gridSpacing: Double = 8,
    ) {
        self.localSettings = localSettings
        self.viewGenerator = viewGenerator
        self.state = state
        self.gridSpacing = gridSpacing
    }

    public var body: some View {
        listOfCodesView
            .navigationTitle(Text(dataModel.feedTitle))
            .task {
                await dataModel.reloadData()
            }
            .onChange(of: dataModel.itemsSearchQuery) { _, _ in
                Task {
                    await dataModel.reloadItems()
                }
            }
            .onChange(of: dataModel.itemsFilteringByTags) { _, _ in
                Task {
                    await dataModel.reloadItems()
                }
            }
    }

    private var currentBehaviour: VaultItemViewBehaviour {
        if state.isEditing {
            .editingState(message: localized(key: "action.tapToView"))
        } else {
            .normal
        }
    }

    private var listOfCodesView: some View {
        @Bindable var dataModel = dataModel
        return ScrollView(.vertical, showsIndicators: true) {
            if dataModel.items.isNotEmpty {
                LazyVGrid(columns: columns) {
                    Section {
                        vaultItemsList
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal)
                .padding(.bottom)
                .animation(.snappy, value: dataModel.itemsFilteringByTags)
            } else {
                ContentUnavailableView {
                    Label(localized(key: "codeFeed.noCodes.title"), systemImage: "key.horizontal")
                }
                .containerRelativeFrame(.vertical)
            }
        }
        .searchable(text: $dataModel.itemsSearchQuery)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                if dataModel.allTags.isNotEmpty {
                    tagFilterBar
                }

                bottomBar
                    .padding(.horizontal)
            }
            .padding(.vertical, 8)
            .animation(.snappy, value: state.isEditing)
            .animation(.snappy, value: dataModel.isSearching)
            .animation(.snappy, value: dataModel.itemsFilteringByTags)
            .animation(.snappy, value: dataModel.allTags.isEmpty)
        }
    }

    /// Horizontally scrolling row of tag filters, presented above the bottom bar.
    private var tagFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(dataModel.allTags) { tag in
                    Toggle(isOn: filterBinding(for: tag)) {
                        Label {
                            Text(tag.name.isBlank ? "Tag" : tag.name)
                        } icon: {
                            TagIconView(iconName: tag.iconName)
                        }
                    }
                    .id(tag)
                    .tint(tag.color.color)
                }
            }
            .toggleStyle(.button)
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .font(.footnote)
            .padding(.horizontal)
        }
        .scrollClipDisabled()
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Item count and the feed-level actions.
    private var bottomBar: some View {
        HStack {
            statusLabel
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            if dataModel.items.isNotEmpty {
                HStack(spacing: 8) {
                    if dataModel.itemsFilteringByTags.isNotEmpty, !state.isEditing {
                        Button {
                            dataModel.itemsFilteringByTags.removeAll()
                        } label: {
                            Label("Clear", systemImage: "tag.slash.fill")
                        }
                        .buttonStyle(.bordered)
                        .tint(.secondary)
                    }

                    Button {
                        state.isEditing.toggle()
                    } label: {
                        Label(
                            state.isEditing ? "Done" : "Edit",
                            systemImage: state.isEditing ? "checkmark" : "pencil",
                        )
                    }
                    .buttonStyle(.borderedProminent)
                }
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .font(.footnote)
                .lineLimit(1)
                .fixedSize()
            }
        }
        .frame(minHeight: 44)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    @ViewBuilder
    private var statusLabel: some View {
        if state.isEditing {
            Label(
                localized(key: "codeFeed.editMode.dragToReorder"),
                systemImage: "arrow.up.arrow.down",
            )
            .lineLimit(1)
        } else {
            let count = dataModel.items.count
            let itemText = count == 1 ? "item" : "items"
            let filterCount = dataModel.itemsFilteringByTags.count

            HStack(spacing: 4) {
                Image(systemName: "key.horizontal")
                Text("\(count) \(itemText)")

                if filterCount > 0 {
                    Text("•")
                    Image(systemName: "tag.fill")
                        .font(.caption)
                    Text("\(filterCount)")
                }
            }
            .lineLimit(1)
        }
    }

    private func filterBinding(for tag: VaultItemTag) -> Binding<Bool> {
        Binding {
            dataModel.itemsFilteringByTags.contains(tag.id)
        } set: { _ in
            dataModel.toggleFiltering(tag: tag.id)
        }
    }

    @State private var targetedIds = Set<Identifier<VaultItem>>()

    private var vaultItemsList: some View {
        ForEach(dataModel.items) { storedItem in
            viewGenerator.makeVaultPreviewView(
                item: storedItem.item,
                metadata: storedItem.metadata,
                behaviour: currentBehaviour,
            )
            .id(makeID(item: storedItem))
            .opacity(targetedIds.contains(storedItem.id) ? 0.5 : 1)
            .draggable(storedItem)
            .if(state.isEditing) {
                $0.dropDestination(for: Identifier<VaultItem>.self) { dropItems, _ in
                    // Semantically, it only makes sense to move or drag a single item at once.
                    guard dropItems.count == 1, let dropItem = dropItems.first else {
                        return false
                    }
                    let reorderer = VaultItemFeedReorderer(state: dataModel.items.map(\.id))
                    let move = reorderer.reorder(item: dropItem, to: storedItem.id)
                    switch move {
                    case .noMove:
                        return false
                    case let .move(move):
                        withAnimation {
                            dataModel.items.move(fromOffsets: [move.fromIndex], toOffset: move.toIndex)
                        }
                        Task {
                            // The list has already moved optimistically. A failed persist leaves the
                            // stored order untouched and the next reload restores the on-disk order.
                            try? await dataModel.reorder(items: [dropItem], to: move.reorderingPosition)
                        }
                        return true
                    }
                } isTargeted: { isTarget in
                    if isTarget {
                        targetedIds.insert(storedItem.id)
                    } else {
                        targetedIds.remove(storedItem.id)
                    }
                }
            }
        }
        .onChange(of: state.isEditing) { _, isEditing in
            if !isEditing {
                targetedIds.removeAll()
            }
        }
    }

    private func makeID(item: VaultItem) -> some Hashable {
        var hasher = Hasher()
        hasher.combine(item.id)
        hasher.combine(state.isEditing)
        hasher.combine(dataModel.itemSearchHash)
        return hasher.finalize()
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 150), spacing: gridSpacing, alignment: .top)]
    }
}

#Preview {
    let store = VaultStoreStub()
    let dataModel = VaultDataModel(
        vaultStore: store,
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
    )
    store.retrieveHandler = { _ in .init(items: [
        .init(
            metadata: .init(
                id: Identifier<VaultItem>(),
                created: Date(),
                updated: Date(),
                relativeOrder: .min,
                userDescription: "My Cool Code",
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
            item: .otpCode(.init(
                type: .totp(),
                data: .init(
                    secret: .empty(),
                    accountName: "example@example.com",
                    issuer: "i",
                ),
            )),
        ),
    ])
    }
    return VaultItemFeedView(
        localSettings: .init(defaults: .init(userDefaults: .standard)),
        viewGenerator: GenericGenerator(),
        state: VaultItemFeedState(),
    )
    .environment(dataModel)
}

private struct GenericGenerator: VaultItemPreviewViewGenerator {
    func makeVaultPreviewView(
        item _: VaultItem.Payload,
        metadata _: VaultItem.Metadata,
        behaviour _: VaultItemViewBehaviour,
    ) -> some View {
        Text("Code")
    }

    func clearViewCache() async {
        // noop
    }

    func scenePhaseDidChange(to _: ScenePhase) {
        // noop
    }

    func didAppear() {
        // noop
    }
}
