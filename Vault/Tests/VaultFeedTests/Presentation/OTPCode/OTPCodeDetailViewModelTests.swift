import Foundation
import FoundationExtensions
import TestHelpers
import Testing
import VaultCore
import VaultFeed

@MainActor
struct OTPCodeDetailViewModelTests {
    @Test
    func init_creatingHasNoSideEffects() {
        let editor = OTPCodeDetailEditorMock()
        _ = makeSUTCreating(editor: editor)

        editor.assertNoOperations()
    }

    @Test
    func init_editingHasNoSideEffects() {
        let editor = OTPCodeDetailEditorMock()
        _ = makeSUTEditing(editor: editor)

        editor.assertNoOperations()
    }

    @Test
    func init_creatingSetsPlaceholderInitialData() {
        let sut = makeSUTCreating()

        #expect(sut.editingModel.detail.issuerTitle == "")
        #expect(sut.editingModel.detail.accountNameTitle == "")
        #expect(sut.editingModel.detail.description == "")
        #expect(sut.editingModel.detail.algorithm == .sha1)
        #expect(sut.editingModel.detail.codeType == .totp)
        #expect(sut.editingModel.detail.hotpCounterValue == 0)
        #expect(sut.editingModel.detail.totpPeriodLength == 30)
        #expect(sut.editingModel.detail.secretBase32String == "")
    }

    @Test
    func init_creatingWithCodeUsesInitialData() {
        let code = OTPAuthCode(
            type: .totp(),
            data: .init(
                secret: .init(data: Data(), format: .base32),
                accountName: "my account",
                issuer: "my issuer",
            ),
        )

        let sut = makeSUTCreating(initialCode: code)

        #expect(sut.editingModel.detail.accountNameTitle == "my account")
        #expect(sut.editingModel.detail.issuerTitle == "my issuer")
        #expect(sut.editingModel.detail.description == "")
    }

    @Test
    func init_creatingStartsUnlockedAndOutOfQuickTypeWithStandardDefaults() {
        let sut = makeSUTCreating(defaults: NewItemDefaults())

        #expect(sut.editingModel.detail.lockState == .notLocked)
        #expect(sut.editingModel.detail.showInQuickType == false)
    }

    @Test(arguments: [false, true], [false, true])
    func init_creatingStartsFromNewItemDefaults(lockNewItems: Bool, showNewCodesInQuickType: Bool) {
        let defaults = NewItemDefaults(lockNewItems: lockNewItems, showNewCodesInQuickType: showNewCodesInQuickType)

        let sut = makeSUTCreating(defaults: defaults)

        #expect(sut.editingModel.detail.lockState.isLocked == lockNewItems)
        #expect(sut.editingModel.detail.showInQuickType == showNewCodesInQuickType)
    }

    @Test(arguments: [false, true], [false, true])
    func init_creatingWithCodeStartsFromNewItemDefaults(lockNewItems: Bool, showNewCodesInQuickType: Bool) {
        let defaults = NewItemDefaults(lockNewItems: lockNewItems, showNewCodesInQuickType: showNewCodesInQuickType)

        let sut = makeSUTCreating(initialCode: anyOTPAuthCode(), defaults: defaults)

        #expect(sut.editingModel.detail.lockState.isLocked == lockNewItems)
        #expect(sut.editingModel.detail.showInQuickType == showNewCodesInQuickType)
    }

    @Test
    func applyScannedCode_keepsNewItemDefaults() {
        let sut = makeSUTCreating(defaults: NewItemDefaults(lockNewItems: true, showNewCodesInQuickType: true))
        sut.startEditing()

        sut.applyScannedCode(anyOTPAuthCode(issuerName: "Scanned"))

        #expect(sut.editingModel.detail.issuerTitle == "Scanned")
        #expect(sut.editingModel.detail.lockState == .lockedWithNativeSecurity)
        #expect(sut.editingModel.detail.showInQuickType == true)
    }

    @Test
    func init_editingKeepsTheCodesOwnLockAndQuickType() {
        let metadata = anyVaultItemMetadata(lockState: .notLocked, showInQuickType: true)

        // Editing never takes new-item defaults, so an existing code keeps what it has.
        let sut = makeSUTEditing(metadata: metadata)

        #expect(sut.editingModel.detail.lockState == .notLocked)
        #expect(sut.editingModel.detail.showInQuickType == true)
    }

    @Test
    func saveChanges_creatingSavesTheNewItemDefaults() async {
        let editor = OTPCodeDetailEditorMock()
        let sut = makeSUTCreating(
            editor: editor,
            defaults: NewItemDefaults(lockNewItems: true, showNewCodesInQuickType: true),
        )

        await confirmation { confirm in
            editor.createCodeHandler = { edits in
                #expect(edits.lockState == .lockedWithNativeSecurity)
                #expect(edits.showInQuickType == true)
                confirm()
            }

            await sut.saveChanges()
        }
    }

    @Test
    func init_editingModelUsesInitialData() {
        let code = OTPAuthCode(
            type: .totp(),
            data: .init(
                secret: .init(data: Data(), format: .base32),
                accountName: "my account",
                issuer: "my issuer",
            ),
        )
        let metadata = anyVaultItemMetadata(userDescription: "my description")

        let sut = makeSUTEditing(code: code, metadata: metadata)

        #expect(sut.editingModel.detail.accountNameTitle == "my account")
        #expect(sut.editingModel.detail.issuerTitle == "my issuer")
        #expect(sut.editingModel.detail.description == "my description")
    }

    @Test
    func detailMenuItems_editingHasItems() {
        let sut = makeSUTEditing()

        #expect(
            sut.detailMenuItems.map(\.title) ==
                ["Created", "Visibility", "Type", "Period", "Digits", "Algorithm", "Key Format"],
        )
    }

    @Test
    func detailMenuItems_creatingHasItems() {
        let sut = makeSUTCreating()

        #expect(sut.detailMenuItems.map(\.title) == ["Visibility"])
    }

    @Test
    func isInEditMode_creatingInitiallyFalse() {
        let sut = makeSUTCreating()

        #expect(!sut.isInEditMode, "Call startEditing manually")
    }

    @Test
    func isInEditMode_editingInitiallyFalse() {
        let sut = makeSUTEditing()

        #expect(!sut.isInEditMode)
    }

    @Test
    func startEditing_setsEditModeTrue() {
        let sut = makeSUTEditing()

        sut.startEditing()

        #expect(sut.isInEditMode)
    }

    @Test
    func isSaving_initiallyFalse() {
        let sut = makeSUT()

        #expect(!sut.isSaving)
    }

    @Test
    func saveChanges_creatingUpdatesEditor() async {
        let editor = OTPCodeDetailEditorMock()
        let sut = makeSUTCreating(editor: editor)

        var handlerCalled = false
        editor.createCodeHandler = { _ in
            handlerCalled = true
        }

        await sut.saveChanges()

        #expect(handlerCalled)
    }

    @Test
    func saveChanges_creatingDoesNotPersistEditingModelWhenSuccessful() async {
        let sut = makeSUTCreating()
        makeDirty(sut: sut)

        await sut.saveChanges()

        #expect(sut.editingModel.isDirty)
    }

    @Test
    func saveChanges_creatingFinishesAfterCreation() async throws {
        let sut = makeSUTCreating()

        try await sut.isFinishedPublisher().expect(valueCount: 1) {
            await sut.saveChanges()
        }
    }

    @Test
    func saveChanges_creatingSendsErrorIfSaveError() async throws {
        let editor = OTPCodeDetailEditorMock()
        editor.createCodeHandler = { _ in
            throw TestError()
        }
        let sut = makeSUTCreating(editor: editor)

        try await sut.didEncounterErrorPublisher().expect(valueCount: 1) {
            await sut.saveChanges()
        }
    }

    @Test
    func saveChanges_creatingSetsSavingToFalseAfterSaveError() async {
        let editor = OTPCodeDetailEditorMock()
        editor.createCodeHandler = { _ in
            throw TestError()
        }
        let sut = makeSUTCreating(editor: editor)

        await sut.saveChanges()

        #expect(!sut.isSaving)
    }

    @Test
    func saveChanges_editingPersistsEditingModelIfSuccessful() async {
        let sut = makeSUTEditing()
        makeDirty(sut: sut)

        await sut.saveChanges()

        #expect(!sut.editingModel.isDirty)
    }

    @Test
    func saveChanges_editingLocksItemWhenLockStateTurnsOn() async {
        let sut = makeSUTEditing(metadata: anyVaultItemMetadata(lockState: .notLocked))
        sut.editingModel.detail.lockState = .lockedWithNativeSecurity

        await sut.saveChanges()

        #expect(sut.isLocked)
    }

    @Test
    func saveChanges_editingDoesNotLockItemWhenLockStateStaysOff() async {
        let sut = makeSUTEditing(metadata: anyVaultItemMetadata(lockState: .notLocked))
        makeDirty(sut: sut)

        await sut.saveChanges()

        #expect(!sut.isLocked)
    }

    @Test
    func saveChanges_editingDoesNotRelockUnlockedItemWhenLockStateStaysOn() async {
        let sut = makeSUTEditing(metadata: anyVaultItemMetadata(lockState: .lockedWithNativeSecurity))
        sut.isLocked = false
        makeDirty(sut: sut)

        await sut.saveChanges()

        #expect(!sut.isLocked)
    }

    @Test
    func saveChanges_editingDoesNotLockItemIfSaveFailed() async {
        let editor = OTPCodeDetailEditorMock()
        editor.updateCodeHandler = { _, _, _ in
            throw TestError()
        }
        let sut = makeSUTEditing(metadata: anyVaultItemMetadata(lockState: .notLocked), editor: editor)
        sut.editingModel.detail.lockState = .lockedWithNativeSecurity

        await sut.saveChanges()

        #expect(!sut.isLocked)
    }

    @Test
    func saveChanges_editingSetsSavingToFalseAfterSaveError() async {
        let editor = OTPCodeDetailEditorMock()
        editor.updateCodeHandler = { _, _, _ in
            throw TestError()
        }
        let sut = makeSUTEditing(editor: editor)

        await sut.saveChanges()

        #expect(!sut.isSaving)
    }

    @Test
    func saveChanges_editingDoesNotPersistEditingModelIfSaveFailed() async {
        let editor = OTPCodeDetailEditorMock()
        editor.updateCodeHandler = { _, _, _ in
            throw TestError()
        }
        let sut = makeSUTEditing(editor: editor)
        makeDirty(sut: sut)

        await sut.saveChanges()

        #expect(sut.editingModel.isDirty)
    }

    @Test
    func saveChanges_editingSendsErrorIfSaveError() async throws {
        let editor = OTPCodeDetailEditorMock()
        editor.updateCodeHandler = { _, _, _ in
            throw TestError()
        }
        let sut = makeSUTEditing(editor: editor)

        try await sut.didEncounterErrorPublisher().expect(valueCount: 1) {
            await sut.saveChanges()
        }
    }

    @Test
    func deleteCode_hasNoActionIfCreatingCode() async {
        let editor = OTPCodeDetailEditorMock()
        let sut = makeSUTCreating(editor: editor)

        await sut.delete()

        editor.assertNoOperations()
    }

    @Test
    func deleteCode_editingIsSavingSetsBackToFalseAfterSuccessfulDelete() async {
        let sut = makeSUTEditing()

        await sut.deleteCode()

        #expect(!sut.isSaving)
    }

    @Test
    func deleteCode_editingSendsFinishSignalOnSuccessfulDeletion() async throws {
        let sut = makeSUTEditing()

        try await sut.isFinishedPublisher().expect(valueCount: 1) {
            await sut.deleteCode()
        }
    }

    @Test
    func deleteCode_editingSendsErrorIfDeleteError() async throws {
        let editor = OTPCodeDetailEditorMock()
        editor.deleteCodeHandler = { _ in
            throw TestError()
        }
        let sut = makeSUTEditing(editor: editor)

        try await sut.didEncounterErrorPublisher().expect(valueCount: 1) {
            await sut.deleteCode()
        }
    }

    @Test
    func done_restoresInitialEditingStateIfInEditMode() {
        let sut = makeSUT()
        sut.startEditing()
        makeDirty(sut: sut)

        sut.done()

        #expect(!sut.editingModel.isDirty)
    }

    @Test
    func done_finishesIfNotInEditMode() async throws {
        let sut = makeSUTEditing()

        try await sut.isFinishedPublisher().expect(valueCount: 1) {
            sut.done()
        }
    }

    @Test
    func editingModel_initialStateUsesData() {
        var code = uniqueCode()
        code.data.accountName = "account name test"
        code.data.issuer = "issuer test"
        var metadata = anyVaultItemMetadata()
        metadata.userDescription = "description test"
        let sut = makeSUTEditing(code: code, metadata: metadata)

        let editing = sut.editingModel

        #expect(editing.initialDetail.accountNameTitle == "account name test")
        #expect(editing.initialDetail.issuerTitle == "issuer test")
        #expect(editing.initialDetail.description == "description test")
    }

    @Test
    func editingModel_editingStateUsesData() {
        var code = uniqueCode()
        code.data.accountName = "account name test"
        code.data.issuer = "issuer test"
        var metadata = anyVaultItemMetadata()
        metadata.userDescription = "description test"
        let sut = makeSUTEditing(code: code, metadata: metadata)

        let editing = sut.editingModel

        #expect(editing.detail.accountNameTitle == "account name test")
        #expect(editing.detail.issuerTitle == "issuer test")
        #expect(editing.detail.description == "description test")
    }

    @Test
    func editingModel_creatingWithoutCodeIsNotInitiallyDirty() {
        let sut = makeSUTCreating(initialCode: nil)

        #expect(
            !sut.editingModel.isDirty,
            "This is not initially dirty because we need the user to input data before we can save.",
        )
    }

    @Test
    func editingModel_creatingWithCodeIsInitiallyDirty() {
        let sut = makeSUTCreating(initialCode: uniqueCode())

        #expect(
            sut.editingModel.isDirty,
            "This is initially dirty as the data has been input from elsewhere. The initial state is hydrated with dirty data.",
        )
    }

    @Test
    func editingModel_editingIsNotInitiallyDirty() {
        let sut = makeSUTEditing()

        #expect(!sut.editingModel.isDirty)
    }

    @Test
    func shouldShowDeleteButton_falseForCreating() {
        let sut = makeSUTCreating()

        #expect(!sut.shouldShowDeleteButton)
    }

    @Test
    func shouldShowDeleteButton_trueForEditing() {
        let sut = makeSUTEditing()

        #expect(sut.shouldShowDeleteButton)
    }

    @Test
    func visibleIssuerTitle_isPlaceholderIfIssuerEmptyString() {
        let sut = makeSUT()
        sut.editingModel.detail.issuerTitle = ""

        #expect(sut.visibleIssuerTitle == "Unnamed")
    }

    @Test
    func visibleIssuerTitle_isUserDefinedTitleIfNotEmptyString() {
        let sut = makeSUT()
        sut.editingModel.detail.issuerTitle = "my issuer"

        #expect(sut.visibleIssuerTitle == "my issuer")
    }

    @Test
    func remainingTags_noTagsSelectedIsEqualToAllTags() {
        let tag1 = anyVaultItemTag()
        let tag2 = anyVaultItemTag()
        let tag3 = anyVaultItemTag()
        let dataModel = anyVaultDataModel()
        dataModel.allTags = [tag1, tag2, tag3]

        let sut = makeSUT(dataModel: dataModel)
        sut.editingModel.detail.tags = []

        #expect(sut.remainingTags == [tag1, tag2, tag3])
    }

    @Test
    func remainingTags_removesTagsThatHaveBeenSelected() {
        let tag1 = anyVaultItemTag()
        let tag2 = anyVaultItemTag()
        let tag3 = anyVaultItemTag()
        let dataModel = anyVaultDataModel()
        dataModel.allTags = [tag1, tag2, tag3]

        let sut = makeSUT(dataModel: dataModel)
        sut.editingModel.detail.tags = [tag1.id]

        #expect(sut.remainingTags == [tag2, tag3])
    }

    @Test
    func tagsThatAreSelected_isEmptyIfNoTagsSelected() {
        let tag1 = anyVaultItemTag()
        let tag2 = anyVaultItemTag()
        let tag3 = anyVaultItemTag()
        let dataModel = anyVaultDataModel()
        dataModel.allTags = [tag1, tag2, tag3]

        let sut = makeSUT(dataModel: dataModel)
        sut.editingModel.detail.tags = []

        #expect(sut.tagsThatAreSelected == [])
    }

    @Test
    func tagsThatAreSelected_matchesSelectedTags() {
        let tag1 = anyVaultItemTag()
        let tag2 = anyVaultItemTag()
        let tag3 = anyVaultItemTag()
        let dataModel = anyVaultDataModel()
        dataModel.allTags = [tag1, tag2, tag3]

        let sut = makeSUT(dataModel: dataModel)
        sut.editingModel.detail.tags = [tag1.id, tag3.id]

        #expect(sut.tagsThatAreSelected == [tag1, tag3])
    }
}

extension OTPCodeDetailViewModelTests {
    private func makeSUTCreating(
        editor: OTPCodeDetailEditorMock = .defaultMock(),
        initialCode: OTPAuthCode? = nil,
        defaults: NewItemDefaults = NewItemDefaults(),
        dataModel: VaultDataModel = VaultDataModel(
            vaultStore: VaultStoreStub(),
            vaultTagStore: VaultTagStoreStub(),
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
        ),
        allTags _: [VaultItemTag] = [],
    ) -> OTPCodeDetailViewModel {
        OTPCodeDetailViewModel(
            mode: .creating(initialCode: initialCode, defaults: defaults),
            dataModel: dataModel,
            editor: editor,
        )
    }

    @MainActor
    private func makeSUTEditing(
        code: OTPAuthCode = uniqueCode(),
        metadata: VaultItem.Metadata = anyVaultItemMetadata(),
        editor: OTPCodeDetailEditorMock = .defaultMock(),
        dataModel: VaultDataModel = VaultDataModel(
            vaultStore: VaultStoreStub(),
            vaultTagStore: VaultTagStoreStub(),
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
        ),
    ) -> OTPCodeDetailViewModel {
        OTPCodeDetailViewModel(
            mode: .editing(code: code, metadata: metadata),
            dataModel: dataModel,
            editor: editor,
        )
    }

    @MainActor
    private func makeSUT(
        code: OTPAuthCode = uniqueCode(),
        metadata: VaultItem.Metadata = anyVaultItemMetadata(),
        editor: OTPCodeDetailEditorMock = .defaultMock(),
        dataModel: VaultDataModel = VaultDataModel(
            vaultStore: VaultStoreStub(),
            vaultTagStore: VaultTagStoreStub(),
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
        ),
    ) -> OTPCodeDetailViewModel {
        OTPCodeDetailViewModel(
            mode: .editing(code: code, metadata: metadata),
            dataModel: dataModel,
            editor: editor,
        )
    }

    @MainActor
    func makeDirty(sut: OTPCodeDetailViewModel) {
        sut.editingModel.detail.accountNameTitle = UUID().uuidString
        #expect(sut.editingModel.isDirty)
    }
}

extension OTPCodeDetailEditorMock {
    static func defaultMock() -> OTPCodeDetailEditorMock {
        OTPCodeDetailEditorMock()
    }

    func assertNoOperations() {
        #expect(createCodeCallCount == 0)
        #expect(updateCodeCallCount == 0)
        #expect(deleteCodeCallCount == 0)
    }
}
