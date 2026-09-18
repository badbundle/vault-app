import Foundation
import FoundationExtensions
import SwiftUI
import TestHelpers
import Testing
import VaultFeed
import VaultSettings
@testable import VaultiOS

@MainActor
final class VaultItemFeedViewSnapshotTests {
    @Test
    func layout_noCodes() async {
        let store = VaultStoreStub()
        let tagStore = VaultTagStoreStub()
        let dataModel = anyVaultDataModel(vaultStore: store, vaultTagStore: tagStore)
        await dataModel.reloadData()

        let sut = makeSUT(dataModel: dataModel)
            .framedForTest()

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func layout_singleCodeAtMediumSize() async {
        let store = VaultStoreStub()
        let tagStore = VaultTagStoreStub()
        store.retrieveHandler = { _ in .init(items: [uniqueVaultItem()]) }
        let dataModel = anyVaultDataModel(vaultStore: store, vaultTagStore: tagStore)
        await dataModel.reloadData()

        let sut = makeSUT(dataModel: dataModel)
            .framedForTest()

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func layout_multipleCodesAtMediumSize() async {
        let store = VaultStoreStub()
        let tagStore = VaultTagStoreStub()
        store.retrieveHandler = { _ in
            .init(items: [
                uniqueVaultItem(),
                uniqueVaultItem(),
                uniqueVaultItem(),
            ])
        }
        let dataModel = anyVaultDataModel(vaultStore: store, vaultTagStore: tagStore)
        await dataModel.reloadData()

        let sut = makeSUT(dataModel: dataModel)
            .framedForTest()

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func viewState_toggleEditingMode() async {
        let state = VaultItemFeedState()
        let store = VaultStoreStub()
        let tagStore = VaultTagStoreStub()
        store.retrieveHandler = { _ in .init(items: [uniqueVaultItem()]) }
        let dataModel = anyVaultDataModel(vaultStore: store, vaultTagStore: tagStore)
        await dataModel.reloadData()

        let sut = makeSUT(dataModel: dataModel, state: state)
            .framedForTest()

        state.isEditing = true
        assertSnapshot(of: sut, as: .image, named: "editing")

        state.isEditing = false
        assertSnapshot(of: sut, as: .image, named: "notEditing")
    }

    @Test
    func searchBar_includesTagsIfTheyExistInTheVaultStore() async {
        let store = VaultStoreStub()
        let tagStore = VaultTagStoreStub()
        tagStore.retrieveTagsHandler = {
            [
                VaultItemTag(id: .init(), name: "tag1"),
                VaultItemTag(id: .init(), name: "tag2", color: .gray),
            ]
        }
        let dataModel = anyVaultDataModel(vaultStore: store, vaultTagStore: tagStore)
        await dataModel.reloadData()

        let sut = makeSUT(dataModel: dataModel)
            .framedForTest()

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func searchBar_tagsBeingFiltered() async {
        let store = VaultStoreStub()
        let tagStore = VaultTagStoreStub()
        let tag1Id = Identifier<VaultItemTag>()
        tagStore.retrieveTagsHandler = {
            [
                VaultItemTag(id: tag1Id, name: "tag1"),
                VaultItemTag(id: .init(), name: "tag2", color: .gray),
            ]
        }
        store.retrieveHandler = { _ in .init(items: [uniqueVaultItem()]) }
        let dataModel = anyVaultDataModel(vaultStore: store, vaultTagStore: tagStore)
        await dataModel.reloadData()

        let sut = makeSUT(dataModel: dataModel)
            .framedForTest()

        dataModel.itemsFilteringByTags = [tag1Id]

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func unifiedBar_searchingWithResults() async {
        let store = VaultStoreStub()
        let tagStore = VaultTagStoreStub()
        store.retrieveHandler = { _ in
            .init(items: [
                uniqueVaultItem(),
                uniqueVaultItem(),
            ])
        }
        let dataModel = anyVaultDataModel(vaultStore: store, vaultTagStore: tagStore)
        await dataModel.reloadData()

        let sut = makeSUT(dataModel: dataModel)
            .framedForTest()

        dataModel.itemsSearchQuery = "test"

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func unifiedBar_searchingWithNoResults() async {
        let store = VaultStoreStub()
        let tagStore = VaultTagStoreStub()
        store.retrieveHandler = { _ in .init(items: []) }
        let dataModel = anyVaultDataModel(vaultStore: store, vaultTagStore: tagStore)
        await dataModel.reloadData()

        let sut = makeSUT(dataModel: dataModel)
            .framedForTest()

        dataModel.itemsSearchQuery = "nonexistent"

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func unifiedBar_tagFilteringInEditMode() async {
        let state = VaultItemFeedState()
        let store = VaultStoreStub()
        let tagStore = VaultTagStoreStub()
        let tag1Id = Identifier<VaultItemTag>()
        tagStore.retrieveTagsHandler = {
            [
                VaultItemTag(id: tag1Id, name: "work"),
                VaultItemTag(id: .init(), name: "personal", color: .tagDefault),
            ]
        }
        store.retrieveHandler = { _ in
            .init(items: [
                uniqueVaultItem(),
                uniqueVaultItem(),
            ])
        }
        let dataModel = anyVaultDataModel(vaultStore: store, vaultTagStore: tagStore)
        await dataModel.reloadData()

        let sut = makeSUT(dataModel: dataModel, state: state)
            .framedForTest()

        dataModel.itemsFilteringByTags = [tag1Id]
        state.isEditing = true

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func unifiedBar_multipleTagsFiltered() async {
        let store = VaultStoreStub()
        let tagStore = VaultTagStoreStub()
        let tag1Id = Identifier<VaultItemTag>()
        let tag2Id = Identifier<VaultItemTag>()
        tagStore.retrieveTagsHandler = {
            [
                VaultItemTag(id: tag1Id, name: "work"),
                VaultItemTag(id: tag2Id, name: "personal", color: .tagDefault),
                VaultItemTag(id: .init(), name: "archive", color: .gray),
            ]
        }
        store.retrieveHandler = { _ in
            .init(items: [
                uniqueVaultItem(),
                uniqueVaultItem(),
                uniqueVaultItem(),
            ])
        }
        let dataModel = anyVaultDataModel(vaultStore: store, vaultTagStore: tagStore)
        await dataModel.reloadData()

        let sut = makeSUT(dataModel: dataModel)
            .framedForTest()

        dataModel.itemsFilteringByTags = [tag1Id, tag2Id]

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func unifiedBar_clearButtonVisible() async {
        let store = VaultStoreStub()
        let tagStore = VaultTagStoreStub()
        let tag1Id = Identifier<VaultItemTag>()
        tagStore.retrieveTagsHandler = {
            [
                VaultItemTag(id: tag1Id, name: "important"),
                VaultItemTag(id: .init(), name: "todo", color: .init(red: 1.0, green: 0.6, blue: 0.0)),
            ]
        }
        store.retrieveHandler = { _ in
            .init(items: [
                uniqueVaultItem(),
                uniqueVaultItem(),
            ])
        }
        let dataModel = anyVaultDataModel(vaultStore: store, vaultTagStore: tagStore)
        await dataModel.reloadData()

        let sut = makeSUT(dataModel: dataModel)
            .framedForTest()

        dataModel.itemsFilteringByTags = [tag1Id]

        assertSnapshot(of: sut, as: .image)
    }

    /// A single active filter is named, so a tag scrolled out of the pill row
    /// is still identifiable from the status label.
    @Test
    func unifiedBar_singleFilterIsNamed() async {
        let store = VaultStoreStub()
        let tagStore = VaultTagStoreStub()
        let tag1Id = Identifier<VaultItemTag>()
        tagStore.retrieveTagsHandler = {
            [
                VaultItemTag(id: tag1Id, name: "work"),
                VaultItemTag(id: .init(), name: "personal", color: .tagDefault),
                VaultItemTag(id: .init(), name: "archive", color: .gray),
            ]
        }
        store.retrieveHandler = { _ in
            .init(items: [uniqueVaultItem(), uniqueVaultItem()])
        }
        let dataModel = anyVaultDataModel(vaultStore: store, vaultTagStore: tagStore)
        await dataModel.reloadData()

        let sut = makeSUT(dataModel: dataModel)
            .framedForTest()

        dataModel.itemsFilteringByTags = [tag1Id]

        assertSnapshot(of: sut, as: .image)
    }

    /// Past one active filter the names would only truncate, so the label
    /// falls back to the pluralized count.
    @Test
    func unifiedBar_multipleFiltersFallBackToCount() async {
        let store = VaultStoreStub()
        let tagStore = VaultTagStoreStub()
        let tag1Id = Identifier<VaultItemTag>()
        let tag2Id = Identifier<VaultItemTag>()
        let tag3Id = Identifier<VaultItemTag>()
        tagStore.retrieveTagsHandler = {
            [
                VaultItemTag(id: tag1Id, name: "work"),
                VaultItemTag(id: tag2Id, name: "personal", color: .tagDefault),
                VaultItemTag(id: tag3Id, name: "archive", color: .gray),
            ]
        }
        store.retrieveHandler = { _ in
            .init(items: [uniqueVaultItem(), uniqueVaultItem()])
        }
        let dataModel = anyVaultDataModel(vaultStore: store, vaultTagStore: tagStore)
        await dataModel.reloadData()

        let sut = makeSUT(dataModel: dataModel)
            .framedForTest()

        dataModel.itemsFilteringByTags = [tag1Id, tag2Id, tag3Id]

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func unifiedBar_narrowWidth_buttonsDoNotWrap() async {
        let store = VaultStoreStub()
        let tagStore = VaultTagStoreStub()
        let tag1Id = Identifier<VaultItemTag>()
        tagStore.retrieveTagsHandler = {
            [
                VaultItemTag(id: tag1Id, name: "work"),
                VaultItemTag(id: .init(), name: "personal", color: .tagDefault),
            ]
        }
        store.retrieveHandler = { _ in
            .init(items: [
                uniqueVaultItem(),
            ])
        }
        let dataModel = anyVaultDataModel(vaultStore: store, vaultTagStore: tagStore)
        await dataModel.reloadData()

        // Use a narrow width to stress-test button wrapping
        let sut = makeSUT(dataModel: dataModel)
            .frame(width: 320, height: 600)

        dataModel.itemsFilteringByTags = [tag1Id]

        assertSnapshot(of: sut, as: .image)
    }

    /// In compact height the tag row and the status bar share one row so the
    /// grid keeps as much of the short screen as possible.
    @Test
    func landscape_collapsesToSingleRow() async {
        let store = VaultStoreStub()
        let tagStore = VaultTagStoreStub()
        let tag1Id = Identifier<VaultItemTag>()
        tagStore.retrieveTagsHandler = {
            [
                VaultItemTag(id: tag1Id, name: "work"),
                VaultItemTag(id: .init(), name: "personal", color: .tagDefault),
                VaultItemTag(id: .init(), name: "archive", color: .gray),
            ]
        }
        store.retrieveHandler = { _ in
            .init(items: [uniqueVaultItem(), uniqueVaultItem()])
        }
        let dataModel = anyVaultDataModel(vaultStore: store, vaultTagStore: tagStore)
        await dataModel.reloadData()

        let sut = makeSUT(dataModel: dataModel)
            .framedForLandscapeTest()

        dataModel.itemsFilteringByTags = [tag1Id]

        assertSnapshot(of: sut, as: .image)
    }

    /// Without tags the compact row is just the status bar, hugging the
    /// trailing edge where it sits when tags are present.
    @Test
    func landscape_noTags_barOnly() async {
        let store = VaultStoreStub()
        store.retrieveHandler = { _ in
            .init(items: [uniqueVaultItem()])
        }
        let dataModel = anyVaultDataModel(vaultStore: store)
        await dataModel.reloadData()

        let sut = makeSUT(dataModel: dataModel)
            .framedForLandscapeTest()

        assertSnapshot(of: sut, as: .image)
    }

    /// With more pills than fit beside the bar, the row must clip at its own
    /// edge rather than let pills run on underneath the bar.
    @Test
    func landscape_overflowingTagsClipBeforeBar() async {
        let store = VaultStoreStub()
        let tagStore = VaultTagStoreStub()
        tagStore.retrieveTagsHandler = {
            ["work", "personal", "archive", "family", "finance", "travel", "health", "projects"]
                .map { VaultItemTag(id: .init(), name: $0) }
        }
        store.retrieveHandler = { _ in
            .init(items: [uniqueVaultItem()])
        }
        let dataModel = anyVaultDataModel(vaultStore: store, vaultTagStore: tagStore)
        await dataModel.reloadData()

        let sut = makeSUT(dataModel: dataModel)
            .framedForLandscapeTest()
            .background(Color.gray)

        assertSnapshot(of: sut, as: .image)
    }

    /// The buttons size the bar, so hiding them on an empty feed must not
    /// change its height. Compare the bar's top edge across the pair.
    @Test
    func bar_keepsHeightWithoutEditButton() async {
        let (empty, populated) = await makeEmptyAndPopulatedDataModels()

        assertSnapshot(
            of: makeSUT(dataModel: empty).framedForTest(height: 240).background(Color.gray),
            as: .image,
            named: "noItems",
        )
        assertSnapshot(
            of: makeSUT(dataModel: populated).framedForTest(height: 240).background(Color.gray),
            as: .image,
            named: "withItems",
        )
    }

    /// A filter that matches nothing hides Edit but must keep Clear, or the
    /// only way out is scrolling back to the pill; the bar keeps its height.
    @Test
    func bar_filterWithNoResultsKeepsClear() async {
        let store = VaultStoreStub()
        let tagStore = VaultTagStoreStub()
        let tag1Id = Identifier<VaultItemTag>()
        tagStore.retrieveTagsHandler = {
            [VaultItemTag(id: tag1Id, name: "work"), VaultItemTag(id: .init(), name: "personal")]
        }
        store.retrieveHandler = { query in
            query.filterTags.isEmpty ? .init(items: [uniqueVaultItem()]) : .init(items: [])
        }
        let dataModel = anyVaultDataModel(vaultStore: store, vaultTagStore: tagStore)
        await dataModel.reloadData()

        dataModel.itemsFilteringByTags = [tag1Id]
        await dataModel.reloadItems()

        let sut = makeSUT(dataModel: dataModel)
            .framedForTest(height: 240)
            .background(Color.gray)

        assertSnapshot(of: sut, as: .image)
    }

    /// Same guarantee for the single-row landscape layout, where the pills
    /// sit beside the bar and would show any height change.
    @Test
    func landscape_barKeepsHeightWithoutEditButton() async {
        let (empty, populated) = await makeEmptyAndPopulatedDataModels()

        assertSnapshot(
            of: makeSUT(dataModel: empty).framedForLandscapeTest().background(Color.gray),
            as: .image,
            named: "noItems",
        )
        assertSnapshot(
            of: makeSUT(dataModel: populated).framedForLandscapeTest().background(Color.gray),
            as: .image,
            named: "withItems",
        )
    }
}

// MARK: - Helpers

extension VaultItemFeedViewSnapshotTests {
    /// Two feeds sharing one tag, one with nothing to edit and one with an
    /// item, so a pair of snapshots differs only by the bar's buttons.
    private func makeEmptyAndPopulatedDataModels() async -> (empty: VaultDataModel, populated: VaultDataModel) {
        let tagStore = VaultTagStoreStub()
        tagStore.retrieveTagsHandler = {
            [VaultItemTag(id: .init(), name: "work"), VaultItemTag(id: .init(), name: "personal")]
        }

        let emptyStore = VaultStoreStub()
        emptyStore.retrieveHandler = { _ in .init(items: []) }
        let empty = anyVaultDataModel(vaultStore: emptyStore, vaultTagStore: tagStore)
        await empty.reloadData()

        let populatedStore = VaultStoreStub()
        populatedStore.retrieveHandler = { _ in .init(items: [uniqueVaultItem()]) }
        let populated = anyVaultDataModel(vaultStore: populatedStore, vaultTagStore: tagStore)
        await populated.reloadData()

        return (empty, populated)
    }

    private func makeSUT(
        dataModel: VaultDataModel,
        state: VaultItemFeedState = VaultItemFeedState(),
        // swiftlint:disable:next force_try
        localSettings: LocalSettings = LocalSettings(defaults: try! .nonPersistent()),
    ) -> some View {
        struct CodePlaceholderView: View {
            var behaviour: VaultItemViewBehaviour

            var body: some View {
                VStack {
                    Text("Code")
                    Text("Placeholder")
                    switch behaviour {
                    case .normal: EmptyView()
                    case let .editingState(message):
                        Text("is editing").font(.caption)
                        if let message {
                            Text(message).font(.caption)
                        }
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .aspectRatio(1, contentMode: .fill)
                .background(Color.blue)
            }
        }
        let generator = VaultItemPreviewViewGeneratorMock.mockGenerating { _, _, behaviour in
            CodePlaceholderView(behaviour: behaviour)
        }
        return VaultItemFeedView(
            localSettings: localSettings,
            viewGenerator: generator,
            state: state,
        )
        .environment(dataModel)
        .environment(VaultInjector(
            clock: EpochClockMock(currentTime: 30),
            intervalTimer: IntervalTimerMock(),
            backupEventLogger: BackupEventLoggerMock(),
            vaultKeyDeriverFactory: VaultKeyDeriverFactoryMock(),
            encryptedVaultDecoder: EncryptedVaultDecoderMock(),
            autoBackupService: AutoBackupServiceMock(status: .disabled, configuration: .init()),
            defaults: Defaults(userDefaults: .standard),
            fileManager: FileManager(),
        ))
    }
}
