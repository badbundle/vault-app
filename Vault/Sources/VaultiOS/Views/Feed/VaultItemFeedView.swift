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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var state: VaultItemFeedState
    @Namespace private var barGlass
    @AccessibilityFocusState private var isStatusBarFocused: Bool

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
            .onChange(of: canCollapseBar) { _, canCollapse in
                // Starting to edit, turning on VoiceOver, or widening to a
                // regular layout brings the full bar straight back.
                if !canCollapse {
                    setBarCollapsed(false)
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
        // Attached to the vertical scroll view itself, before anything that
        // wraps it, so the pill row's horizontal scrolling is never seen.
        .onScrollPhaseChange { _, phase in
            state.barTracker.phaseChanged(to: phase)
        }
        .onScrollGeometryChange(for: FeedScrollPosition.self) { geometry in
            FeedScrollPosition(geometry)
        } action: { _, position in
            guard let change = state.barTracker.scrolled(to: position, canCollapse: canCollapseBar) else { return }
            setBarCollapsed(change == .collapse)
        }
        .searchable(text: $dataModel.itemsSearchQuery)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        // A bar rather than an inset so the system draws its scroll edge
        // effect: tiles fade and blur beneath the glass instead of running
        // straight into it.
        .safeAreaBar(edge: .bottom, spacing: 0) {
            Group {
                if verticalSizeClass == .compact {
                    compactFeedBar
                } else {
                    regularFeedBar
                }
            }
            .padding(.vertical, 6)
            .animation(.snappy, value: state.isEditing)
            .animation(.snappy, value: dataModel.isSearching)
            // Filter changes get a much shorter spring than the rest: the
            // default one fades the filter name and Clear button out over
            // ~0.4s while the glass capsule morphs, which reads as the bar
            // lagging behind the tap rather than animating with it.
            .animation(.snappy(duration: 0.2), value: dataModel.itemsFilteringByTags)
            .animation(.snappy, value: dataModel.allTags.isEmpty)
        }
    }

    // MARK: - Collapsing

    /// Collapsing follows the system tab bar, which only minimizes in compact
    /// layouts. It never happens mid-edit, so Done stays in reach, or under
    /// VoiceOver, so the filters are never a hidden step away.
    private var canCollapseBar: Bool {
        !state.isEditing
            && !voiceOverEnabled
            && (horizontalSizeClass == .compact || verticalSizeClass == .compact)
    }

    /// Checked again at render time so the full bar shows whenever editing,
    /// whatever order state changes arrive in.
    private var showsCollapsedBar: Bool {
        state.isBarCollapsed && !state.isEditing
    }

    private var barAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .snappy
    }

    /// Glass surfaces that morph into each other as the bar collapses. Under
    /// Reduce Motion they have no identity, so they crossfade instead.
    private func barGlassID(_ id: FeedBarGlassID) -> FeedBarGlassID? {
        reduceMotion ? nil : id
    }

    private var barGlassTransition: GlassEffectTransition {
        reduceMotion ? .materialize : .matchedGeometry
    }

    /// One transaction for the bar and the safe area it gives back, so the
    /// glass morph and the feed's resize move together.
    private func setBarCollapsed(_ isCollapsed: Bool) {
        guard state.isBarCollapsed != isCollapsed else { return }
        withAnimation(barAnimation) {
            state.isBarCollapsed = isCollapsed
        }
    }

    // MARK: - Bar layouts

    /// Tag filters stacked above the status bar, for regular-height layouts.
    ///
    /// Everything shares one glass container so the pills and status bar can
    /// morph into the collapsed capsule. The pill row spans the screen and
    /// doesn't clip here, so the container can sit outside its scroll view.
    private var regularFeedBar: some View {
        GlassEffectContainer {
            // No spacing: the pills' 44pt hit targets already leave a gap
            // between the drawn pills and the status bar.
            VStack(spacing: 0) {
                if showsCollapsedBar {
                    collapsedBar
                } else {
                    if dataModel.allTags.isNotEmpty {
                        tagFilterBar(ownsGlassContainer: false)
                    }

                    bottomBar
                        .padding(.horizontal)
                }
            }
        }
    }

    /// Tag filters and the status bar side by side, for compact-height
    /// layouts (iPhone landscape) where two rows would crowd out the grid.
    private var compactFeedBar: some View {
        HStack(spacing: 8) {
            if dataModel.allTags.isNotEmpty, !showsCollapsedBar {
                tagFilterBar(ownsGlassContainer: true)
            } else {
                // Keep the bar trailing where it sits when tags are present.
                Spacer()
            }

            // The pills clip, so they keep their own container; the status
            // bar and the collapsed capsule share this one to morph in place.
            GlassEffectContainer {
                if showsCollapsedBar {
                    collapsedBar
                } else {
                    bottomBar
                }
            }
            // Hugging its content collapses the bar's internal spacer so the
            // tag row takes whatever width is left.
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal)
    }

    /// Horizontally scrolling row of tag filters.
    ///
    /// - Parameter ownsGlassContainer: Whether the pills get a container of
    ///   their own inside the scroll view. Glass renders at the container's
    ///   level, so when the row clips, a container outside the scroll view
    ///   would let pills draw past its edge.
    private func tagFilterBar(ownsGlassContainer: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            // The container clips to its bounds, and the pill stroke straddles
            // the capsule edge; the pills' 44pt hit targets leave it room
            // above and below so the border isn't shaved.
            if ownsGlassContainer {
                GlassEffectContainer {
                    pillRow
                }
            } else {
                pillRow
            }
        }
        // Side by side with the bar the scroll view no longer spans the
        // screen, so it must clip or pills would slide underneath the bar.
        .scrollClipDisabled(verticalSizeClass != .compact)
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
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
                    .glassEffectID(barGlassID(.tag(tag.id)), in: barGlass)
                    .glassEffectTransition(barGlassTransition)
                    .glassSnapshotBackdrop(in: .capsule)
                    // The plain button style draws nothing, so the whole
                    // 44pt frame is tappable while the pill stays compact.
                    .frame(minHeight: 44)
                    .contentShape(.rect)
                }
                .id(tag)
            }
        }
        .toggleStyle(.button)
        .buttonStyle(.plain)
        .controlSize(.small)
        .font(.footnote)
        // Beside the bar the scroll view clips, so the row keeps a hair of
        // inset or the first pill's stroke is shaved at the leading edge;
        // stacked, it spans the screen and carries the normal margin.
        .padding(.horizontal, verticalSizeClass == .compact ? 2 : 16)
    }

    /// Item count and the feed-level actions.
    private var bottomBar: some View {
        HStack {
            statusLabel
                .font(.subheadline)
                .foregroundStyle(.secondary)
                // Lands focus here when the collapsed capsule is expanded,
                // since the element that had focus is gone.
                .accessibilityFocused($isStatusBarFocused)

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
        // without the heavy, opaque panel a flat fill would need. The
        // buttons' hit targets set the height, so there is no vertical padding.
        .frame(minHeight: 44)
        .padding(.horizontal, 14)
        .glassEffect(.regular, in: .capsule)
        .glassEffectID(barGlassID(.status), in: barGlass)
        .glassEffectTransition(barGlassTransition)
        .glassSnapshotBackdrop(in: .capsule)
        .transition(.opacity)
    }

    /// The whole bar minimized to one capsule while scrolling down: the item
    /// count and any active filter, so the feed's scope stays visible. Tapping
    /// it brings the filters and actions back.
    private var collapsedBar: some View {
        Button {
            state.barTracker.resetTravel()
            setBarCollapsed(false)
            isStatusBarFocused = true
        } label: {
            statusLabel
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .glassEffectID(barGlassID(.status), in: barGlass)
        .glassEffectTransition(barGlassTransition)
        .glassSnapshotBackdrop(in: .capsule)
        .transition(.opacity)
        .accessibilityLabel(collapsedBarAccessibilityLabel)
        .accessibilityHint(localized(key: "codeFeed.bar.collapsed.accessibilityHint"))
    }

    /// The collapsed capsule read as a sentence rather than its glyphs.
    ///
    /// The count always comes from `itemsCountDescription`, which never
    /// reveals items hidden behind a search passphrase.
    private var collapsedBarAccessibilityLabel: String {
        let count = dataModel.itemsCountDescription
        switch activeFilterSummary {
        case .none:
            return count
        case let .named(name):
            return localized(key: "codeFeed.bar.collapsed.filteredByTag.\(count).\(name)")
        case .count:
            return localized(
                key: "codeFeed.bar.collapsed.filteredByTags.\(count).\(dataModel.filteringByTagsDescription)",
            )
        }
    }

    private var clearButton: some View {
        Button {
            dataModel.itemsFilteringByTags.removeAll()
        } label: {
            Label("Clear", systemImage: "tag.slash.fill")
        }
        .buttonStyle(MinimumHitTargetButtonStyle(base: .bordered))
        .tint(.secondary)
    }

    /// Edit is a secondary action, so at rest it matches Clear's monochrome
    /// bezel and only Done — the action that ends the mode — is tinted.
    @ViewBuilder
    private var editButton: some View {
        let button = Button {
            state.isEditing.toggle()
        } label: {
            Label(
                state.isEditing ? "Done" : "Edit",
                systemImage: state.isEditing ? "checkmark" : "pencil",
            )
        }
        if state.isEditing {
            button.buttonStyle(MinimumHitTargetButtonStyle(base: .borderedProminent))
        } else {
            button
                .buttonStyle(MinimumHitTargetButtonStyle(base: .bordered))
                .tint(.secondary)
        }
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

                if let filterDescription = activeFilterSummary.shortDescription {
                    Group {
                        Text("•")
                        Image(systemName: "tag.fill")
                            .font(.caption)
                    }
                    .accessibilityHidden(true)
                    Text(filterDescription)
                }
            }
            .lineLimit(1)
        }
    }

    /// The active tag filters, shared by the visible status label and the
    /// collapsed capsule's spoken label.
    ///
    /// The filter pills scroll horizontally, so an active tag can sit
    /// off-screen; naming it keeps that state visible. Only a single name
    /// fits beside the item count and the Clear/Edit buttons, so past one
    /// filter this falls back to the bare count.
    private var activeFilterSummary: ActiveFilterSummary {
        let activeIDs = dataModel.itemsFilteringByTags
        guard activeIDs.isNotEmpty else { return .none }
        guard activeIDs.count == 1, let activeID = activeIDs.first else {
            return .count(activeIDs.count)
        }

        // A filter whose tag is no longer in `allTags` has no name to show.
        guard let tag = dataModel.allTags.first(where: { $0.id == activeID }) else {
            return .count(activeIDs.count)
        }

        return .named(tag.name.isBlank ? "Tag" : tag.name)
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

/// Identities of the feed bar's glass surfaces, so they morph into one
/// another as the bar collapses and expands.
private enum FeedBarGlassID: Hashable, Sendable {
    /// The status bar, and the collapsed capsule it becomes.
    case status
    case tag(Identifier<VaultItemTag>)
}

private enum ActiveFilterSummary: Equatable {
    case none
    case named(String)
    case count(Int)

    /// The filter as shown beside the item count, or `nil` when none apply.
    var shortDescription: String? {
        switch self {
        case .none: nil
        case let .named(name): name
        case let .count(count): "\(count)"
        }
    }
}

// In a navigation stack so the bottom search field and the scroll edge effect
// under the bar show as they do in the app. Scroll to watch the bar collapse.
#Preview {
    NavigationStack {
        makeFeedPreview()
    }
}

#Preview("Landscape", traits: .landscapeLeft) {
    NavigationStack {
        makeFeedPreview()
    }
}

@MainActor
private func makeFeedPreview() -> some View {
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
