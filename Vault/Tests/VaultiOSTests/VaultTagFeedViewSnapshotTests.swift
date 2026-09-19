import Foundation
import SwiftUI
import TestHelpers
import Testing
import VaultFeed
@testable import VaultiOS

@MainActor
final class VaultTagFeedViewSnapshotTests {
    @Test
    func layout_noTags() async {
        let sut = await makeSUT()
            .framedForTest()

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func layout_multipleTags() async {
        let vaultTagStore = VaultTagStoreStub()
        vaultTagStore.retrieveTagsHandler = {
            [
                anyVaultItemTag(name: "A", color: .gray, iconName: "tag.fill"),
                anyVaultItemTag(name: "Barcellos", color: .tagDefault, iconName: "person.fill"),
                anyVaultItemTag(name: "Zoo", color: .gray, iconName: "tag.fill"),
                anyVaultItemTag(name: "Crayfish", color: .gray, iconName: "tag.fill"),
                anyVaultItemTag(name: "Snow", color: .white, iconName: "snowflake"),
            ]
        }
        let sut = await makeSUT(vaultTagStore: vaultTagStore)
            .framedForTest()

        assertSnapshot(of: sut, as: .image)
    }
}

// MARK: - Helpers

extension VaultTagFeedViewSnapshotTests {
    private func makeSUT(
        vaultTagStore: any VaultTagStore = VaultTagStoreStub(),
    ) async -> some View {
        let dataModel = VaultDataModel(
            vaultStore: VaultStoreStub(),
            vaultTagStore: vaultTagStore,
            vaultImporter: VaultStoreImporterMock(),
            vaultDeleter: VaultStoreDeleterMock(),
            vaultKillphraseDeleter: VaultStoreKillphraseDeleterMock(),
            vaultOtpAutofillStore: VaultOTPAutofillStoreMock(),
            backupPasswordStore: BackupPasswordStoreMock(),
            killphraseKeyStore: StubKillphraseKeyStore(),
            killphraseRehashService: nil,
            searchPassphraseKeyStore: StubSearchPassphraseKeyStore(),
            searchPassphraseRehashService: nil,
            backupEventLogger: BackupEventLoggerMock(),
        )
        await dataModel.reloadData()
        return VaultTagFeedView(viewModel: .init())
            .environment(dataModel)
    }
}
