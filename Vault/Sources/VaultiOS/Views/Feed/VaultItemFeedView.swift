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
    @FocusState private var isSearchFieldFocused: Bool
    /// Set when the person opens search, so the field takes focus as soon as
    /// it appears rather than every time the bar expands to show it.
    @State private var focusesSearchFieldOnAppear = false
    /// The bar's height when last expanded, which it keeps while collapsed.
    @State private var expandedBarHeight: CGFloat?

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
                // Starting to edit or type a search, turning on VoiceOver, or
                // widening to a regular layout brings the full bar straight
                // back.
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
        ScrollView(.vertical, showsIndicators: true) {
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
        // Scrolling the results puts the keyboard away, which also frees the
        // bar to collapse.
        .scrollDismissesKeyboard(.immediately)
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
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                if !showsCollapsedBar {
                    expandedBarHeight = height
                }
            }
            // Collapsing only changes how the bar looks, never the space it
            // takes: the bar's height is the feed's bottom inset, and
            // changing that mid-scroll moves the content under the finger
            // and cuts the bounce at the bottom short.
            .frame(minHeight: showsCollapsedBar ? expandedBarHeight : nil, alignment: .bottom)
            .animation(.snappy, value: state.isEditing)
            .animation(.snappy, value: dataModel.isSearching)
            .animation(.snappy, value: showsSearchField)
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
    /// layouts. It never happens mid-edit, so Done stays in reach, while
    /// typing a search, or under VoiceOver, so the filters are never a hidden
    /// step away.
    private var canCollapseBar: Bool {
        !state.isEditing
            && !isSearchFieldFocused
            && !voiceOverEnabled
            && (horizontalSizeClass == .compact || verticalSizeClass == .compact)
    }

    /// Checked again at render time so the full bar shows whenever editing
    /// or typing, whatever order state changes arrive in.
    private var showsCollapsedBar: Bool {
        state.isBarCollapsed && !state.isEditing && !isSearchFieldFocused
    }

    /// Whether search is open, showing its field (or, while collapsed, its
    /// query) in place of the search button. A query is never hidden, however
    /// it was set.
    private var showsSearchField: Bool {
        state.isSearchPresented || dataModel.itemsSearchQuery.isNotEmpty
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

    private func setBarCollapsed(_ isCollapsed: Bool) {
        guard state.isBarCollapsed != isCollapsed else { return }
        withAnimation(barAnimation) {
            state.isBarCollapsed = isCollapsed
        }
    }

    // MARK: - Searching

    /// Expands the bar with the search field open and focused.
    private func openSearch() {
        state.barTracker.resetTravel()
        focusesSearchFieldOnAppear = true
        withAnimation(barAnimation) {
            state.isBarCollapsed = false
            state.isSearchPresented = true
        }
    }

    /// Clears the query and puts the search button back.
    private func closeSearch() {
        isSearchFieldFocused = false
        focusesSearchFieldOnAppear = false
        withAnimation(barAnimation) {
            state.isSearchPresented = false
            dataModel.itemsSearchQuery = ""
        }
    }

    // MARK: - Bar layouts

    /// Tag filters above the status bar and search, for regular-height
    /// layouts. The status bar sits leading with the search button trailing;
    /// opening search lifts the status bar onto a row of its own so the
    /// field can take the full width beneath it.
    ///
    /// Everything shares one glass container so the pills, status bar and
    /// search can morph as the bar collapses and search opens. The pill row
    /// spans the screen and doesn't clip here, so the container can sit
    /// outside its scroll view.
    private var regularFeedBar: some View {
        GlassEffectContainer {
            // No spacing: the pills' 44pt hit targets already leave a gap
            // between the drawn pills and the status bar.
            VStack(spacing: 0) {
                if dataModel.allTags.isNotEmpty, !showsCollapsedBar {
                    tagFilterBar(ownsGlassContainer: false)
                }

                HStack(spacing: 8) {
                    if showsCollapsedBar {
                        collapsedBar
                        Spacer(minLength: 0)
                    } else {
                        statusBar
                    }

                    if !showsSearchField || showsCollapsedBar {
                        searchButton
                    }
                }
                .padding(.horizontal)

                if showsSearchField, !showsCollapsedBar {
                    searchFieldRow
                        .padding(.horizontal)
                        .padding(.top, 8)
                }
            }
        }
    }

    /// Status bar, tag filters and search button in one row, for
    /// compact-height layouts (iPhone landscape) where stacking them would
    /// crowd out the grid. An open search field takes a second row.
    private var compactFeedBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                // The pills clip, so they keep their own container; the
                // status bar and the collapsed capsule share this one to
                // morph in place.
                GlassEffectContainer {
                    if showsCollapsedBar {
                        collapsedBar
                    } else {
                        statusBar
                    }
                }
                // Hugging its content collapses the bar's internal spacer so
                // the tag row takes whatever width is left.
                .fixedSize(horizontal: true, vertical: false)

                if dataModel.allTags.isNotEmpty, !showsCollapsedBar {
                    tagFilterBar(ownsGlassContainer: true)
                } else {
                    // Keep search trailing where it sits when tags are present.
                    Spacer(minLength: 0)
                }

                if !showsSearchField || showsCollapsedBar {
                    GlassEffectContainer {
                        searchButton
                    }
                }
            }

            if showsSearchField, !showsCollapsedBar {
                GlassEffectContainer {
                    searchFieldRow
                }
            }
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
                // The same glass pill that shows a tag everywhere else,
                // tinted while its filter is active, which reads far more
                // clearly than tinting a bordered button both ways. The
                // toggle keeps the button trait and selected state that a
                // bare tap gesture would not expose.
                Toggle(isOn: filterBinding(for: tag)) {
                    TagPillView(
                        tag: tag,
                        isSelected: dataModel.itemsFilteringByTags.contains(tag.id),
                        isInteractive: true,
                    )
                    .glassEffectID(barGlassID(.tag(tag.id)), in: barGlass)
                    .glassEffectTransition(barGlassTransition)
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
        // Beside the bar the scroll view clips, so the row keeps a hair of
        // inset or the first pill's stroke is shaved at the leading edge;
        // stacked, it spans the screen and carries the normal margin.
        .padding(.horizontal, verticalSizeClass == .compact ? 2 : 16)
    }

    /// Item count and the feed-level actions.
    private var statusBar: some View {
        // Where the label and the button titles don't all fit, as on a
        // narrow phone beside the search button, the buttons drop their
        // titles before the count is truncated.
        ViewThatFits(in: .horizontal) {
            statusBarRow(iconOnlyButtons: false)
            statusBarRow(iconOnlyButtons: true)
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

    private func statusBarRow(iconOnlyButtons: Bool) -> some View {
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
            .labelStyle(StatusBarButtonLabelStyle(iconOnly: iconOnlyButtons))
            .buttonBorderShape(.capsule)
            .controlSize(.small)
            .font(.footnote)
            .lineLimit(1)
            .fixedSize()
        }
    }

    /// The status bar and filters minimized to one capsule while scrolling
    /// down: the item count and any active filter, so the feed's scope stays
    /// visible. Tapping it brings the filters and actions back.
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
    private var collapsedBarAccessibilityLabel: String {
        let count = countDescription
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
                Image(systemName: dataModel.isSearching ? "magnifyingglass" : "key.horizontal")
                Text(countDescription)
                    // On a narrow bar the filter name truncates first.
                    .layoutPriority(1)

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

    /// What the feed is showing: its items, or while searching, the matches.
    ///
    /// Both count only what the feed displays, so neither reveals items
    /// hidden behind a search passphrase.
    private var countDescription: String {
        dataModel.isSearching ? dataModel.itemsMatchCountDescription : dataModel.itemsCountDescription
    }

    // MARK: - Search controls

    /// Opens search. While the bar is collapsed with a search open, it also
    /// carries the query, and tapping it goes back to editing that.
    ///
    /// One capsule whatever it shows, so its glass morphs into the field and
    /// back; with only the glyph it is a circle.
    private var searchButton: some View {
        Button {
            openSearch()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.body.weight(.medium))

                if showsSearchField, dataModel.itemsSearchQuery.isNotEmpty {
                    Text(dataModel.itemsSearchQuery)
                        .font(.subheadline)
                        .lineLimit(1)
                        .frame(maxWidth: 120, alignment: .leading)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.trailing, 6)
                }
            }
            .frame(minWidth: 44, minHeight: 44)
            .padding(.horizontal, showsSearchField && dataModel.itemsSearchQuery.isNotEmpty ? 10 : 0)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .keyboardShortcut("f", modifiers: .command)
        .glassEffect(.regular.interactive(), in: .capsule)
        .glassEffectID(barGlassID(.search), in: barGlass)
        .glassEffectTransition(barGlassTransition)
        .glassSnapshotBackdrop(in: .capsule)
        .transition(.opacity)
        .accessibilityLabel("Search")
        .accessibilityValue(showsSearchField ? dataModel.itemsSearchQuery : "")
    }

    /// The search field, with a button to close search beside it.
    private var searchFieldRow: some View {
        @Bindable var dataModel = dataModel
        return HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                TextField("Search", text: $dataModel.itemsSearchQuery)
                    .focused($isSearchFieldFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit {
                        isSearchFieldFocused = false
                    }

                if dataModel.itemsSearchQuery.isNotEmpty {
                    Button {
                        dataModel.itemsSearchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 44)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear Text")
                }
            }
            // The clear button carries its own margin.
            .padding(.leading, 14)
            .padding(.trailing, dataModel.itemsSearchQuery.isNotEmpty ? 6 : 14)
            .frame(minHeight: 44)
            // The whole capsule focuses the field, not just its text.
            .contentShape(.capsule)
            .onTapGesture {
                isSearchFieldFocused = true
            }
            .glassEffect(.regular, in: .capsule)
            .glassEffectID(barGlassID(.search), in: barGlass)
            .glassEffectTransition(barGlassTransition)
            .glassSnapshotBackdrop(in: .capsule)
            .onAppear {
                guard focusesSearchFieldOnAppear else { return }
                focusesSearchFieldOnAppear = false
                isSearchFieldFocused = true
            }

            Button {
                closeSearch()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.medium))
                    .frame(width: 44, height: 44)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .glassEffectID(barGlassID(.closeSearch), in: barGlass)
            .glassEffectTransition(barGlassTransition)
            .glassSnapshotBackdrop(in: .circle)
            .accessibilityLabel("Close Search")
        }
        .transition(.opacity)
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

        return .named(tag.displayName)
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
    /// The search button, and the field it opens into.
    case search
    case closeSearch
}

/// The status bar's buttons with their titles, or with only their icons when
/// space is short. Either way the title stays as the accessibility label.
private struct StatusBarButtonLabelStyle: LabelStyle {
    var iconOnly: Bool

    func makeBody(configuration: Configuration) -> some View {
        if iconOnly {
            Label(configuration).labelStyle(.iconOnly)
        } else {
            Label(configuration).labelStyle(.titleAndIcon)
        }
    }
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
