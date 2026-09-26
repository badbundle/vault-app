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
    ) -> some View {
        NavigationStack {
            BackupHomeView()
        }
        .environment(dataModel)
        .environment(DeviceAuthenticationService(policy: .alwaysAllow))
        .environment(anyVaultInjector())
        .framedForTest()
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

    private func restoreDataModel(hasItems: Bool) async -> VaultDataModel {
        let vaultStore = VaultStoreStub()
        vaultStore.hasAnyItemsHandler = { hasItems }
        let dataModel = anyVaultDataModel(vaultStore: vaultStore)
        await dataModel.reloadData()
        return dataModel
    }

    private func restoreViewModel(policy: some DeviceAuthenticationPolicy) -> BackupRestoreViewModel {
        BackupRestoreViewModel(authenticationService: DeviceAuthenticationService(policy: policy))
    }
}
