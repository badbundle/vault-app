import CryptoEngine
import Foundation
import SwiftUI
import TestHelpers
import Testing
import VaultFeed
@testable import VaultiOS

@MainActor
struct BackupViewSnapshotTests {
    @Test
    func backupHome_noBackup() {
        let sut = makeBackupHomeSUT(dataModel: anyVaultDataModel(backupPasswordStore: unknownStatusPasswordStore()))

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func backupHome_staleBackup() {
        let backupEventLogger = BackupEventLoggerMock()
        backupEventLogger.lastBackupEventHandler = {
            VaultBackupEvent(
                backupDate: Date(timeIntervalSince1970: 1_600_000_000),
                eventDate: Date(timeIntervalSince1970: 1_600_000_000),
                kind: .exportedToPDF,
                payloadHash: .init(value: Data(repeating: 0xAB, count: 32)),
            )
        }
        let sut = makeBackupHomeSUT(dataModel: anyVaultDataModel(
            backupPasswordStore: unknownStatusPasswordStore(),
            backupEventLogger: backupEventLogger,
        ))

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func backupHome_passwordNotSet() async {
        let backupPasswordStore = BackupPasswordStoreMock()
        backupPasswordStore.fetchPasswordMetadataHandler = { nil }
        let dataModel = anyVaultDataModel(backupPasswordStore: backupPasswordStore)
        await dataModel.loadBackupPasswordStatus()

        let sut = makeBackupHomeSUT(dataModel: dataModel)

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func backupHome_passwordSet() async {
        let backupPasswordStore = BackupPasswordStoreMock()
        backupPasswordStore.fetchPasswordMetadataHandler = {
            .init(lastSetDate: Date(timeIntervalSince1970: 1_700_000_000))
        }
        let dataModel = anyVaultDataModel(backupPasswordStore: backupPasswordStore)
        await dataModel.loadBackupPasswordStatus()

        let sut = makeBackupHomeSUT(dataModel: dataModel)

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func backupHome_vaultSetAside() {
        let sut = makeBackupHomeSUT(
            dataModel: anyVaultDataModel(backupPasswordStore: unknownStatusPasswordStore()),
            vaultStoreArchives: setAsideVaults(count: 1),
            height: 1300,
        )

        assertSnapshot(of: sut, as: .image)
    }

    /// With no passcode there's nothing to authenticate deleting with, so the button is off and the footer says why.
    @Test
    func backupHome_vaultSetAside_withoutPasscode() {
        let sut = makeBackupHomeSUT(
            dataModel: anyVaultDataModel(backupPasswordStore: unknownStatusPasswordStore()),
            vaultStoreArchives: setAsideVaults(count: 1),
            policy: .cannotAuthenticate,
            height: 1300,
        )

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func backupHome_vaultsSetAside_dark() {
        let sut = makeBackupHomeSUT(
            dataModel: anyVaultDataModel(backupPasswordStore: unknownStatusPasswordStore()),
            vaultStoreArchives: setAsideVaults(count: 2),
            height: 1300,
        )

        assertSnapshot(of: sut, colorScheme: .dark)
    }

    @Test
    func backupExport_passwordNotFetched() {
        let sut = makeBackupExportSUT(dataModel: anyVaultDataModel())

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func backupExport_passwordError() async {
        let backupPasswordStore = BackupPasswordStoreMock()
        backupPasswordStore.fetchPasswordHandler = { throw TestError() }
        let dataModel = anyVaultDataModel(backupPasswordStore: backupPasswordStore)
        await dataModel.loadBackupPassword()
        await dataModel.reloadData()

        let sut = makeBackupExportSUT(dataModel: dataModel)

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func backupExport_passwordNotCreated() async {
        let backupPasswordStore = BackupPasswordStoreMock()
        backupPasswordStore.fetchPasswordHandler = { nil }
        let dataModel = anyVaultDataModel(backupPasswordStore: backupPasswordStore)
        await dataModel.loadBackupPassword()
        await dataModel.reloadData()

        let sut = makeBackupExportSUT(dataModel: dataModel)

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func backupExport_passwordFetched() async {
        let backupPasswordStore = BackupPasswordStoreMock()
        backupPasswordStore.fetchPasswordHandler = { .init(
            key: .random(),
            salt: .random(count: 32),
            keyDervier: .testing,
        ) }
        let dataModel = anyVaultDataModel(backupPasswordStore: backupPasswordStore)
        await dataModel.loadBackupPassword()
        await dataModel.reloadData()

        let sut = makeBackupExportSUT(dataModel: dataModel)

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func backupExport_passwordFetched_largeText() async {
        let backupPasswordStore = BackupPasswordStoreMock()
        backupPasswordStore.fetchPasswordHandler = { .init(
            key: .random(),
            salt: .random(count: 32),
            keyDervier: .testing,
        ) }
        let dataModel = anyVaultDataModel(backupPasswordStore: backupPasswordStore)
        await dataModel.loadBackupPassword()
        await dataModel.reloadData()

        let sut = makeBackupExportSUT(dataModel: dataModel, dynamicTypeSize: .accessibility2, height: 1500)

        assertSnapshot(of: sut, as: .image)
    }

    /// Locked over a vault with items, so the reference would change if any restore option showed.
    @Test
    func backupRestore_locked() async {
        let sut = makeBackupRestoreSUT(
            dataModel: await restoreDataModel(hasItems: true),
            viewModel: restoreViewModel(policy: .alwaysAllow),
        )

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func backupRestore_locked_dark() async {
        let sut = makeBackupRestoreSUT(
            dataModel: await restoreDataModel(hasItems: true),
            viewModel: restoreViewModel(policy: .alwaysAllow),
        )

        assertSnapshot(of: sut, colorScheme: .dark)
    }

    @Test
    func backupRestore_authenticationFailed() async {
        let viewModel = restoreViewModel(policy: .alwaysDeny)
        await viewModel.authenticate()
        let sut = makeBackupRestoreSUT(
            dataModel: await restoreDataModel(hasItems: true),
            viewModel: viewModel,
        )

        assertSnapshot(of: sut, as: .image)
    }

    /// With no passcode there's nothing to authenticate with, so the page says a passcode is needed.
    @Test
    func backupRestore_passcodeRequired() async {
        let sut = makeBackupRestoreSUT(
            dataModel: await restoreDataModel(hasItems: false),
            viewModel: restoreViewModel(policy: .cannotAuthenticate),
        )

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func backupRestore_passcodeRequired_dark() async {
        let sut = makeBackupRestoreSUT(
            dataModel: await restoreDataModel(hasItems: false),
            viewModel: restoreViewModel(policy: .cannotAuthenticate),
        )

        assertSnapshot(of: sut, colorScheme: .dark)
    }

    @Test
    func backupRestore_unlockedEmptyVault() async {
        let viewModel = restoreViewModel(policy: .alwaysAllow)
        await viewModel.authenticate()
        let sut = makeBackupRestoreSUT(
            dataModel: await restoreDataModel(hasItems: false),
            viewModel: viewModel,
        )

        assertSnapshot(of: sut, as: .image)
    }

    /// A vault holding only items that a search shows gets the same sections as an empty one: it matches
    /// `backupRestore_unlockedEmptyVault`'s reference.
    @Test
    func backupRestore_unlockedWithOnlyItemsASearchShows_isTheSameAsAnEmptyVault() async {
        let viewModel = restoreViewModel(policy: .alwaysAllow)
        await viewModel.authenticate()
        let sut = makeBackupRestoreSUT(
            dataModel: await restoreDataModel(hasItems: false, hasHiddenItems: true),
            viewModel: viewModel,
        )

        assertSnapshot(of: sut, as: .image, named: "1", testName: "backupRestore_unlockedEmptyVault()")
    }

    @Test
    func backupRestore_unlockedWithItems() async {
        let viewModel = restoreViewModel(policy: .alwaysAllow)
        await viewModel.authenticate()
        let sut = makeBackupRestoreSUT(
            dataModel: await restoreDataModel(hasItems: true),
            viewModel: viewModel,
        )

        assertSnapshot(of: sut, as: .image)
    }
}

extension BackupViewSnapshotTests {
    /// A store whose password status can't be read, so the hub falls back to its neutral password row.
    private func unknownStatusPasswordStore() -> BackupPasswordStoreMock {
        let store = BackupPasswordStoreMock()
        store.fetchPasswordMetadataHandler = { throw TestError() }
        return store
    }

    private func makeBackupHomeSUT(
        dataModel: VaultDataModel,
        vaultStoreArchives: any VaultStoreArchiving = NoVaultStoreArchives(),
        policy: some DeviceAuthenticationPolicy = .alwaysAllow,
        height: CGFloat = 1000,
    ) -> some View {
        NavigationStack {
            BackupHomeView()
        }
        .environment(dataModel)
        .environment(DeviceAuthenticationService(policy: policy))
        .environment(anyVaultInjector(vaultStoreArchives: vaultStoreArchives))
        .framedForTest(height: height)
    }

    private func setAsideVaults(count: Int) -> VaultStoreArchivingMock {
        let archives = VaultStoreArchivingMock()
        let dates = (0 ..< count).map { Date(timeIntervalSince1970: 1_700_000_000 + Double($0) * 86400) }
        archives.archivesHandler = {
            dates.map { VaultStoreArchive(url: URL(fileURLWithPath: "/tmp/\($0.timeIntervalSince1970)"), date: $0) }
        }
        return archives
    }

    private func makeBackupExportSUT(
        dataModel: VaultDataModel,
        dynamicTypeSize: DynamicTypeSize = .large,
        height: CGFloat = 1000,
    ) -> some View {
        NavigationStack {
            BackupExportView()
        }
        .environment(dataModel)
        .environment(DeviceAuthenticationService(policy: .alwaysAllow))
        .environment(anyVaultInjector())
        .dynamicTypeSize(dynamicTypeSize)
        .framedForTest(height: height)
    }

    private func makeBackupRestoreSUT(
        dataModel: VaultDataModel,
        viewModel: BackupRestoreViewModel,
    ) -> some View {
        NavigationStack {
            BackupRestoreView(viewModel: viewModel)
        }
        .environment(dataModel)
        .environment(anyVaultInjector())
        .framedForTest()
    }

    /// A data model over a store with items that show in the feed, if `hasItems`, and items that only a search
    /// shows, if `hasHiddenItems`.
    private func restoreDataModel(hasItems: Bool, hasHiddenItems: Bool = false) async -> VaultDataModel {
        let vaultStore = VaultStoreStub()
        vaultStore.hasAnyItemsHandler = { hasItems || hasHiddenItems }
        vaultStore.retrieveHandler = { query in
            let shows = query.filterText == nil ? hasItems : hasHiddenItems
            return .init(items: shows ? [uniqueVaultItem()] : [])
        }
        let dataModel = anyVaultDataModel(vaultStore: vaultStore)
        await dataModel.reloadData()
        return dataModel
    }

    private func restoreViewModel(policy: some DeviceAuthenticationPolicy) -> BackupRestoreViewModel {
        BackupRestoreViewModel(authenticationService: DeviceAuthenticationService(policy: policy))
    }
}
