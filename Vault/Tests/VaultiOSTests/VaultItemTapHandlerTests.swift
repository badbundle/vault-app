import Foundation
import LocalAuthentication
import TestHelpers
import Testing
import VaultFeed
import VaultSettings
@testable import VaultiOS

@MainActor
struct VaultItemTapHandlerTests {
    // MARK: - Tapping a code

    @Test
    func tap_code_copySetting_copies() async throws {
        let copy = anyCopyAction()
        let (sut, recorder, policy) = makeSUT(previewAction: .copyText(copy))

        try await sut.tap(.new(), isEditing: false, codeTapAction: .copy)

        #expect(recorder.copied == [copy])
        #expect(recorder.shown.isEmpty)
        #expect(policy.authenticateWithBiometricsCallCount == 0)
    }

    @Test
    func tap_code_showDetailsSetting_showsDetailsWithoutCopying() async throws {
        let id = Identifier<VaultItem>.new()
        let (sut, recorder, policy) = makeSUT(previewAction: .copyText(anyCopyAction()))

        try await sut.tap(id, isEditing: false, codeTapAction: .showDetails)

        #expect(recorder.shown == [id])
        #expect(recorder.copied.isEmpty)
        #expect(policy.authenticateWithBiometricsCallCount == 0)
    }

    @Test
    func tap_lockedCode_copySetting_authenticatesThenCopies() async throws {
        let copy = anyCopyAction(requiresAuthentication: true)
        let (sut, recorder, policy) = makeSUT(previewAction: .copyText(copy), authenticates: true)

        try await sut.tap(.new(), isEditing: false, codeTapAction: .copy)

        #expect(policy.authenticateWithBiometricsCallCount == 1)
        #expect(recorder.copied == [copy])
    }

    @Test
    func tap_lockedCode_copySetting_authenticationFails_copiesNothing() async throws {
        let (sut, recorder, _) = makeSUT(
            previewAction: .copyText(anyCopyAction(requiresAuthentication: true)),
            authenticates: false,
        )

        try await sut.tap(.new(), isEditing: false, codeTapAction: .copy)

        #expect(recorder.copied.isEmpty)
        #expect(recorder.shown.isEmpty)
    }

    @Test
    func tap_lockedCode_copySetting_authenticationCancelled_throwsAndCopiesNothing() async {
        let (sut, recorder, policy) = makeSUT(previewAction: .copyText(anyCopyAction(requiresAuthentication: true)))
        policy.authenticateWithBiometricsHandler = { _ in throw LAError(.userCancel) }

        await #expect(throws: LAError.self) {
            try await sut.tap(.new(), isEditing: false, codeTapAction: .copy)
        }
        #expect(recorder.copied.isEmpty)
    }

    @Test
    func tap_lockedCode_showDetailsSetting_showsDetailsWithoutAuthenticating() async throws {
        // Opening it reveals nothing: the detail page asks for authentication itself.
        let id = Identifier<VaultItem>.new()
        let (sut, recorder, policy) = makeSUT(previewAction: .copyText(anyCopyAction(requiresAuthentication: true)))

        try await sut.tap(id, isEditing: false, codeTapAction: .showDetails)

        #expect(recorder.shown == [id])
        #expect(recorder.copied.isEmpty)
        #expect(policy.authenticateWithBiometricsCallCount == 0)
    }

    // MARK: - Tapping anything else

    @Test(arguments: CodeTapAction.allCases)
    func tap_itemWithNothingToCopy_showsDetails(codeTapAction: CodeTapAction) async throws {
        let id = Identifier<VaultItem>.new()
        let (sut, recorder, _) = makeSUT(previewAction: .openItemDetail(id))

        try await sut.tap(id, isEditing: false, codeTapAction: codeTapAction)

        #expect(recorder.shown == [id])
        #expect(recorder.copied.isEmpty)
    }

    @Test(arguments: CodeTapAction.allCases)
    func tap_itemWithNoAction_doesNothing(codeTapAction: CodeTapAction) async throws {
        let (sut, recorder, _) = makeSUT(previewAction: nil)

        try await sut.tap(.new(), isEditing: false, codeTapAction: codeTapAction)

        #expect(recorder.shown.isEmpty)
        #expect(recorder.copied.isEmpty)
    }

    // MARK: - Edit mode

    @Test(arguments: CodeTapAction.allCases)
    func tap_editing_code_showsDetails(codeTapAction: CodeTapAction) async throws {
        let id = Identifier<VaultItem>.new()
        let (sut, recorder, policy) = makeSUT(previewAction: .copyText(anyCopyAction(requiresAuthentication: true)))

        try await sut.tap(id, isEditing: true, codeTapAction: codeTapAction)

        #expect(recorder.shown == [id])
        #expect(recorder.copied.isEmpty)
        #expect(policy.authenticateWithBiometricsCallCount == 0)
    }

    @Test(arguments: CodeTapAction.allCases)
    func tap_editing_otherItem_showsDetails(codeTapAction: CodeTapAction) async throws {
        let id = Identifier<VaultItem>.new()
        let (sut, recorder, _) = makeSUT(previewAction: .openItemDetail(id))

        try await sut.tap(id, isEditing: true, codeTapAction: codeTapAction)

        #expect(recorder.shown == [id])
    }

    // MARK: - Menu

    @Test
    func menuActions_code_offersCopyAndShowDetails() {
        let (sut, _, _) = makeSUT(previewAction: .copyText(anyCopyAction()))

        #expect(sut.menuActions(for: .new(), isEditing: false) == [.copy, .showDetails])
    }

    @Test
    func menuActions_itemWithNothingToCopy_offersNothing() {
        let id = Identifier<VaultItem>.new()
        let (sut, _, _) = makeSUT(previewAction: .openItemDetail(id))

        #expect(sut.menuActions(for: id, isEditing: false).isEmpty)
    }

    @Test
    func menuActions_editing_offersNothing() {
        let (sut, _, _) = makeSUT(previewAction: .copyText(anyCopyAction()))

        #expect(sut.menuActions(for: .new(), isEditing: true).isEmpty)
    }

    @Test
    func perform_copy_copiesTheCodeAsItIsNow() async throws {
        let handler = StubPreviewActionHandler(action: .copyText(anyCopyAction(text: "111111")))
        let (sut, recorder, _) = makeSUT(previewActionHandler: handler)
        let id = Identifier<VaultItem>.new()
        #expect(sut.menuActions(for: id, isEditing: false) == [.copy, .showDetails])

        // The code moves on while the menu is open.
        handler.action = .copyText(anyCopyAction(text: "222222"))
        try await sut.perform(.copy, on: id)

        #expect(recorder.copied.map(\.text) == ["222222"])
    }

    @Test
    func perform_copy_lockedCode_authenticatesFirst() async throws {
        let copy = anyCopyAction(requiresAuthentication: true)
        let (sut, recorder, policy) = makeSUT(previewAction: .copyText(copy), authenticates: false)

        try await sut.perform(.copy, on: .new())

        #expect(policy.authenticateWithBiometricsCallCount == 1)
        #expect(recorder.copied.isEmpty)
    }

    @Test
    func perform_showDetails_showsDetails() async throws {
        let id = Identifier<VaultItem>.new()
        let (sut, recorder, _) = makeSUT(previewAction: .copyText(anyCopyAction()))

        try await sut.perform(.showDetails, on: id)

        #expect(recorder.shown == [id])
        #expect(recorder.copied.isEmpty)
    }
}

// MARK: - Helpers

extension VaultItemTapHandlerTests {
    private func makeSUT(
        previewAction: VaultItemPreviewAction?,
        authenticates: Bool = true,
    ) -> (VaultItemTapHandler, TapRecorder, DeviceAuthenticationPolicyMock) {
        makeSUT(previewActionHandler: StubPreviewActionHandler(action: previewAction), authenticates: authenticates)
    }

    private func makeSUT(
        previewActionHandler: StubPreviewActionHandler,
        authenticates: Bool = true,
    ) -> (VaultItemTapHandler, TapRecorder, DeviceAuthenticationPolicyMock) {
        let recorder = TapRecorder()
        let policy = DeviceAuthenticationPolicyMock(
            canAuthenicateWithPasscode: true,
            canAuthenticateWithBiometrics: true,
        )
        policy.authenticateWithBiometricsHandler = { _ in authenticates }
        let sut = VaultItemTapHandler(
            previewActionHandler: previewActionHandler,
            authenticationService: DeviceAuthenticationService(policy: policy),
            copy: { recorder.copied.append($0) },
            showDetails: { recorder.shown.append($0) },
        )
        return (sut, recorder, policy)
    }

    private func anyCopyAction(text: String = "123456", requiresAuthentication: Bool = false) -> VaultTextCopyAction {
        VaultTextCopyAction(text: text, requiresAuthenticationToCopy: requiresAuthentication, contentType: .otp)
    }
}

@MainActor
private final class TapRecorder {
    var copied = [VaultTextCopyAction]()
    var shown = [Identifier<VaultItem>]()
}

@MainActor
private final class StubPreviewActionHandler: VaultItemPreviewActionHandler {
    var action: VaultItemPreviewAction?

    init(action: VaultItemPreviewAction?) {
        self.action = action
    }

    func previewActionForVaultItem(id _: Identifier<VaultItem>) -> VaultItemPreviewAction? {
        action
    }
}
