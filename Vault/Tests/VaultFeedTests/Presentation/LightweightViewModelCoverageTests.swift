import Foundation
import Testing
@testable import VaultFeed

@MainActor
struct LightweightViewModelCoverageTests {
    @Test
    func backupRestoreViewModel_exposesStrings() {
        let sut = BackupRestoreViewModel()

        #expect(sut.strings.homeTitle.isEmpty == false)
        #expect(sut.strings.backupPasswordImportTitle.isEmpty == false)
    }

    @Test
    func vaultTagFeedViewModel_exposesStrings() {
        let sut = VaultTagFeedViewModel()

        #expect(sut.strings.title.isEmpty == false)
        #expect(sut.strings.createTagTitle.isEmpty == false)
        #expect(sut.strings.noTagsTitle.isEmpty == false)
        #expect(sut.strings.noTagsDescription.isEmpty == false)
        #expect(sut.strings.retrieveErrorTitle.isEmpty == false)
        #expect(sut.strings.retrieveErrorDescription.isEmpty == false)
    }

    @Test
    func genericVaultItemCopyActionHandler_returnsFirstChildAction() {
        let itemID = Identifier<VaultItem>.new()
        let first = VaultItemCopyActionHandlerMock()
        let second = VaultItemCopyActionHandlerMock()
        let expected = VaultTextCopyAction(text: "123456", requiresAuthenticationToCopy: false, contentType: .otp)
        first.textToCopyForVaultItemHandler = { _ in nil }
        second.textToCopyForVaultItemHandler = { id in
            #expect(id == itemID)
            return expected
        }
        let sut = GenericVaultItemCopyActionHandler(childHandlers: [first, second])

        let action = sut.textToCopyForVaultItem(id: itemID)

        #expect(action == expected)
        #expect(first.textToCopyForVaultItemCallCount == 1)
        #expect(second.textToCopyForVaultItemCallCount == 1)
    }

    @Test
    func genericVaultItemCopyActionHandler_returnsNilWhenNoChildMatches() {
        let child = VaultItemCopyActionHandlerMock()
        let sut = GenericVaultItemCopyActionHandler(childHandlers: [child])

        let action = sut.textToCopyForVaultItem(id: .new())

        #expect(action == nil)
        #expect(child.textToCopyForVaultItemCallCount == 1)
    }
}
