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
        VStack {
            listOfCodesView
        }
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
                .animation(.easeOut(duration: 0.1), value: dataModel.itemsFilteringByTags)
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
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(dataModel.allTags) { tag in
                                TagPillView(tag: tag, isSelected: dataModel.itemsFilteringByTags.contains(tag.id))
                                    .id(tag)
                                    .onTapGesture {
                                        dataModel.toggleFiltering(tag: tag.id)
                                    }
                            }
                        }
                        .font(.footnote)
                    }
                    .scrollClipDisabled()
                    .padding(.horizontal)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                unifiedInfoSection
                    .padding(.horizontal)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            .padding(.top, 8)
            .padding(.bottom, 8)
            .animation(.spring(response: 0.3, dampingFraction: 1.0), value: state.isEditing)
            .animation(.spring(response: 0.3, dampingFraction: 1.0), value: dataModel.isSearching)
            .animation(.spring(response: 0.3, dampingFraction: 1.0), value: dataModel.itemsFilteringByTags.count)
            .animation(.spring(response: 0.3, dampingFraction: 1.0), value: dataModel.allTags.isEmpty)
        }
    }

    /// Unified bottom section with item count, filtering status, and action buttons
    private var unifiedInfoSection: some View {
        HStack {
            // Left side: Item count or drag to reorder message
            if state.isEditing {
                Label {
                    Text(localized(key: "codeFeed.editMode.dragToReorder"))
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "arrow.up.arrow.down")
                        .foregroundColor(.secondary)
                }
            } else {
                let count = dataModel.items.count
                let itemText = count == 1 ? "item" : "items"
                let filterCount = dataModel.itemsFilteringByTags.count

                HStack(spacing: 4) {
                    Image(systemName: "key.horizontal")
                        .foregroundColor(.secondary)
                    Text("\(count) \(itemText)")
                        .foregroundColor(.secondary)

                    if filterCount > 0 {
                        Text("•")
                            .foregroundColor(.secondary)
                        Image(systemName: "tag.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("\(filterCount)")
                            .foregroundColor(.secondary)
                    }
                }
                .font(.subheadline)
                .lineLimit(1)
            }

            Spacer()

            // Right side: Action buttons
            if dataModel.items.isNotEmpty {
                HStack(spacing: 8) {
                    // Clear button when filtering by tags
                    if dataModel.itemsFilteringByTags.isNotEmpty, !state.isEditing {
                        Button {
                            dataModel.itemsFilteringByTags.removeAll()
                        } label: {
                            Label("Clear", systemImage: "tag.slash.fill")
                                .lineLimit(1)
                        }
                        .fontWeight(.semibold)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(Color.secondary)
                        .clipShape(Capsule())
                        .fixedSize()
                    }

                    // Edit/Done button
                    Button {
                        state.isEditing.toggle()
                    } label: {
                        Label(
                            state.isEditing ? "Done" : "Edit",
                            systemImage: state.isEditing ? "checkmark" : "pencil",
                        )
                        .lineLimit(1)
                    }
                    .fontWeight(.semibold)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
                    .fixedSize()
                }
            }
        }
        .frame(minHeight: 44)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
            if !isEditing { targetedIds.removeAll() }
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
