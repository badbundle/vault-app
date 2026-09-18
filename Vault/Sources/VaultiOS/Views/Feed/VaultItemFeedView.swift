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
    @Environment(\.verticalSizeClass) private var verticalSizeClass
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
            Group {
                if verticalSizeClass == .compact {
                    compactFeedBar
                } else {
                    regularFeedBar
                }
            }
            .padding(.vertical, 6)
            // Filter changes deliberately don't animate here: fading the
            // filter name and Clear button out while the glass capsule
            // morphs reads as the bar lagging behind the tap.
            .animation(.snappy, value: state.isEditing)
            .animation(.snappy, value: dataModel.isSearching)
            .animation(.snappy, value: dataModel.allTags.isEmpty)
        }
    }

    /// Plain regular glass lets tile text show straight through the bar, so
    /// a wash of the background colour sits behind the glass to keep it
    /// legible over busy content while keeping the glass edge and lensing.
    ///
    /// This is a backdrop rather than `Glass.tint` because a tinted glass
    /// renders as an empty image under `CALayer.render(in:)`, which blanks
    /// every snapshot test that includes the feed.
    private var feedBarWash: Color {
        Color(.systemBackground).opacity(0.85)
    }

    /// Tag filters stacked above the status bar, for regular-height layouts.
    private var regularFeedBar: some View {
        VStack(spacing: 6) {
            if dataModel.allTags.isNotEmpty {
                tagFilterBar
            }

            bottomBar
                .padding(.horizontal)
        }
    }

    /// Tag filters and the status bar side by side, for compact-height
    /// layouts (iPhone landscape) where two rows would crowd out the grid.
    private var compactFeedBar: some View {
        HStack(spacing: 8) {
            if dataModel.allTags.isNotEmpty {
                tagFilterBar
            } else {
                // Keep the bar trailing where it sits when tags are present.
                Spacer()
            }

            // Hugging its content collapses the bar's internal spacer so the
            // tag row takes whatever width is left.
            bottomBar
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal)
    }

    /// Horizontally scrolling row of tag filters.
    private var tagFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            // The container lives inside the scroll view on purpose: glass
            // renders at the container's level, so a container outside the
            // scroll view would let pills draw past its clip.
            GlassEffectContainer {
                pillRow
            }
        }
        // Side by side with the bar the scroll view no longer spans the
        // screen, so it must clip or pills would slide underneath the bar.
        .scrollClipDisabled(verticalSizeClass != .compact)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var pillRow: some View {
        HStack {
            ForEach(dataModel.allTags) { tag in
                // `TagPillView` draws its own capsule — filled when
                // selected, outlined when not — which reads far more
                // clearly than tinting a bordered button both ways.
                // Glass beneath it keeps the pill legible over whatever
                // scrolls past. The toggle keeps the button trait and
                // selected state that a bare tap gesture would not expose.
                Toggle(isOn: filterBinding(for: tag)) {
                    TagPillView(
                        tag: tag,
                        isSelected: dataModel.itemsFilteringByTags.contains(tag.id),
                    )
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .background(feedBarWash, in: .capsule)
                }
                .id(tag)
            }
        }
        .toggleStyle(.button)
        .buttonStyle(.plain)
        .controlSize(.small)
        .font(.footnote)
        .padding(.horizontal, verticalSizeClass == .compact ? 0 : 16)
    }

    /// Item count and the feed-level actions.
    private var bottomBar: some View {
        HStack {
            statusLabel
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            // The buttons are what give the row its height, so an invisible
            // zero-width Edit button always sits behind them: the bar stays
            // the same height whether the feed is empty, filtered to nothing,
            // or full, without reserving any width when they are gone.
            ZStack(alignment: .trailing) {
                editButton
                    .hidden()
                    .frame(width: 0)

                HStack(spacing: 8) {
                    // Clear follows the filter, not the results, so a filter
                    // that matches nothing can still be cleared from here.
                    if dataModel.itemsFilteringByTags.isNotEmpty, !state.isEditing {
                        clearButton
                    }

                    if dataModel.items.isNotEmpty {
                        editButton
                    }
                }
            }
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .font(.footnote)
            .lineLimit(1)
            .fixedSize()
        }
        // Glass keeps the row legible over the grid scrolling beneath it
        // without the heavy, opaque panel a flat fill would need.
        .padding(.vertical, 6)
        .padding(.horizontal, 14)
        .glassEffect(.regular, in: .capsule)
        .background(feedBarWash, in: .capsule)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var clearButton: some View {
        Button {
            dataModel.itemsFilteringByTags.removeAll()
        } label: {
            Label("Clear", systemImage: "tag.slash.fill")
        }
        .buttonStyle(.bordered)
        .tint(.secondary)
    }

    private var editButton: some View {
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

    @ViewBuilder
    private var statusLabel: some View {
        if state.isEditing {
            Label(
                localized(key: "codeFeed.editMode.dragToReorder"),
                systemImage: "arrow.up.arrow.down",
            )
            .lineLimit(1)
        } else {
            HStack(spacing: 4) {
                Image(systemName: "key.horizontal")
                Text(dataModel.itemsCountDescription)

                if let filterDescription {
                    Text("•")
                    Image(systemName: "tag.fill")
                        .font(.caption)
                    Text(filterDescription)
                }
            }
            .lineLimit(1)
        }
    }

    /// Describes the active tag filters, or `nil` when none are applied.
    ///
    /// The filter pills scroll horizontally, so an active tag can sit
    /// off-screen; naming it keeps that state visible. Only a single name
    /// fits beside the item count and the Clear/Edit buttons, so past one
    /// filter this falls back to the bare count.
    private var filterDescription: String? {
        let activeIDs = dataModel.itemsFilteringByTags
        guard activeIDs.isNotEmpty else { return nil }
        guard activeIDs.count == 1, let activeID = activeIDs.first else {
            return "\(activeIDs.count)"
        }

        // A filter whose tag is no longer in `allTags` has no name to show.
        guard let tag = dataModel.allTags.first(where: { $0.id == activeID }) else {
            return "\(activeIDs.count)"
        }

        return tag.name.isBlank ? "Tag" : tag.name
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
    let tagStore = VaultTagStoreStub()
    let workTag = Identifier<VaultItemTag>()
    tagStore.retrieveTagsHandler = {
        [
            VaultItemTag(id: workTag, name: "work"),
            VaultItemTag(id: .init(), name: "personal", color: .tagDefault),
            VaultItemTag(id: .init(), name: "archive", color: .gray),
            VaultItemTag(id: .init(), name: "family", color: .init(color: .purple)),
        ]
    }
    let dataModel = VaultDataModel(
        vaultStore: store,
        vaultTagStore: tagStore,
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
    // Enough tiles to scroll under the bar, so the glass has content behind it.
    let colors: [Color] = [.green, .orange, .blue, .pink, .teal, .indigo, .red, .mint, .brown, .cyan]
    store.retrieveHandler = { _ in
        .init(items: colors.enumerated().map { index, color in
            .init(
                metadata: .init(
                    id: Identifier<VaultItem>(),
                    created: Date(),
                    updated: Date(),
                    relativeOrder: .min,
                    userDescription: "My Cool Code \(index + 1)",
                    tags: index.isMultiple(of: 2) ? [workTag] : [],
                    visibility: .always,
                    searchableLevel: .full,
                    searchPassphrase: nil,
                    killphrase: nil,
                    lockState: .notLocked,
                    color: VaultItemColor(color: color),
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
            )
        })
    }
    return VaultItemFeedView(
        localSettings: .init(defaults: .init(userDefaults: .standard)),
        viewGenerator: GenericGenerator(),
        state: VaultItemFeedState(),
    )
    .environment(dataModel)
    .environment(VaultInjector(
        clock: EpochClockMock(currentTime: 30),
        intervalTimer: IntervalTimerImpl(),
        backupEventLogger: BackupEventLoggerMock(),
        vaultKeyDeriverFactory: VaultKeyDeriverFactoryImpl(),
        encryptedVaultDecoder: EncryptedVaultDecoderMock(),
        autoBackupService: AutoBackupServiceMock(status: .disabled, configuration: .init()),
        defaults: Defaults(userDefaults: .standard),
        fileManager: .default,
    ))
}

private struct GenericGenerator: VaultItemPreviewViewGenerator {
    func makeVaultPreviewView(
        item _: VaultItem.Payload,
        metadata: VaultItem.Metadata,
        behaviour _: VaultItemViewBehaviour,
    ) -> some View {
        // Solid tiles so the glass bar has something to blur behind it.
        Text(metadata.userDescription)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 160)
            .background(metadata.color?.color ?? .gray, in: .rect(cornerRadius: 12))
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
