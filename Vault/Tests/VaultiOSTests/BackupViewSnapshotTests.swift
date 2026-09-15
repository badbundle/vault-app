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
        let sut = makeBackupHomeSUT(dataModel: anyVaultDataModel())

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
        let sut = makeBackupHomeSUT(dataModel: anyVaultDataModel(backupEventLogger: backupEventLogger))

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
    func backupRestore_noItems() async {
        let vaultStore = VaultStoreStub()
        vaultStore.hasAnyItemsHandler = { false }
        let dataModel = anyVaultDataModel(vaultStore: vaultStore)
        await dataModel.reloadData()

        let sut = makeBackupRestoreSUT(dataModel: dataModel)
            .framedForTest()

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func backupRestore_hasItems() async {
        let vaultStore = VaultStoreStub()
        vaultStore.hasAnyItemsHandler = { true }
        let dataModel = anyVaultDataModel(vaultStore: vaultStore)
        await dataModel.reloadData()

        let sut = makeBackupRestoreSUT(dataModel: dataModel)
            .framedForTest()

        assertSnapshot(of: sut, as: .image)
    }
}

extension BackupViewSnapshotTests {
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
    ) -> some View {
        NavigationStack {
            BackupExportView()
        }
        .environment(dataModel)
        .environment(DeviceAuthenticationService(policy: .alwaysAllow))
        .environment(anyVaultInjector())
        .framedForTest()
    }

    private func makeBackupRestoreSUT(
        dataModel: VaultDataModel,
    ) -> some View {
        let injector = anyVaultInjector()
        return BackupRestoreView()
            .environment(dataModel)
            .environment(injector)
    }
}
