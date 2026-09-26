import Foundation
import TestHelpers
import Testing
import VaultCore
import VaultFeed

@MainActor
struct SecureNoteDetailViewModelTests {
    @Test
    func init_creatingHasNoSideEffects() {
        let editor = SecureNoteDetailEditorMock()
        _ = makeSUTCreating(editor: editor)

        editor.assertNoOperationsPerformed()
    }

    @Test
    func init_editingHasNoSideEffects() {
        let editor = SecureNoteDetailEditorMock()
        _ = makeSUTEditing(editor: editor)

        editor.assertNoOperationsPerformed()
    }

    @Test
    func init_editingModelUsesInitialData() {
        let note = SecureNote(title: "my title", contents: "first line\nsecond line", format: .plain)
        let metadata = anyVaultItemMetadata()
        let sut = makeSUTEditing(storedNote: note, storedMetadata: metadata)

        #expect(sut.editingModel.detail.titleLine == "first line")
        #expect(sut.editingModel.detail.contents == note.contents)
        #expect(sut.editingModel.detail.textFormat == .plain)
    }

    @Test
    func init_editingModelUsesInitialEncryptionKey() {
        let key = DerivedEncryptionKey(key: .random(), salt: .random(count: 32), keyDervier: .testing)
        let sut = makeSUTEditing(existingKey: key)

        #expect(sut.editingModel.detail.existingEncryptionKey == key)
    }

    @Test
    func init_creatingSetsBlankInitialData() {
        let sut = makeSUTCreating()

        #expect(sut.editingModel.detail.titleLine == "")
        #expect(sut.editingModel.detail.contents == "")
        #expect(sut.editingModel.detail.textFormat == .markdown)
        #expect(sut.editingModel.detail.newEncryptionPassword == "")
        #expect(sut.editingModel.detail.existingEncryptionKey == nil)
    }

    @Test(arguments: [false, true])
    func init_creatingStartsFromNewItemDefaults(lockNewItems: Bool) {
        let sut = makeSUTCreating(defaults: NewItemDefaults(lockNewItems: lockNewItems))

        #expect(sut.editingModel.detail.lockState.isLocked == lockNewItems)
    }

    @Test
    func init_editingKeepsTheNotesOwnLock() {
        let metadata = anyVaultItemMetadata(lockState: .notLocked)

        // Editing never takes new-item defaults, so an existing note keeps what it has.
        let sut = makeSUTEditing(storedMetadata: metadata)

        #expect(sut.editingModel.detail.lockState == .notLocked)
    }

    @Test
    func saveChanges_creatingSavesTheNewItemDefaults() async {
        let editor = SecureNoteDetailEditorMock()
        let sut = makeSUTCreating(editor: editor, defaults: NewItemDefaults(lockNewItems: true))

        await confirmation { confirm in
            editor.createNoteHandler = { edits in
                #expect(edits.lockState == .lockedWithNativeSecurity)
                confirm()
            }

            await sut.saveChanges()
        }
    }

    @Test
    func isInEditMode_editingInitiallyFalse() {
        let sut = makeSUTEditing()

        #expect(sut.isInEditMode == false)
    }

    @Test
    func isInEditMode_creatingInitiallyFalse() {
        let sut = makeSUTCreating()

        #expect(sut.isInEditMode == false)
    }

    @Test
    func startEditing_setsEditModeTrue() {
        let sut = makeSUTEditing()

        sut.startEditing()

        #expect(sut.isInEditMode)
    }

    @Test
    func isSaving_isInitiallyFalse() {
        let sut = makeSUTEditing()

        #expect(sut.isSaving == false)
    }

    @Test
    func saveChanges_creatingUpdatesEditor() async {
        let editor = SecureNoteDetailEditorMock()
        let sut = makeSUTCreating(editor: editor)

        await confirmation { confirmation in
            editor.createNoteHandler = { _ in
                confirmation.confirm()
            }

            await sut.saveChanges()
        }
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
        let editor = SecureNoteDetailEditorMock()
        editor.createNoteHandler = { _ in
            throw TestError()
        }
        let sut = makeSUTCreating(editor: editor)

        try await sut.didEncounterErrorPublisher().expect(valueCount: 1) {
            await sut.saveChanges()
        }
    }

    @Test
    func saveChanges_creatingSetsSavingToFalseAfterSaveError() async {
        let editor = SecureNoteDetailEditorMock()
        editor.createNoteHandler = { _ in
            throw TestError()
        }
        let sut = makeSUTCreating(editor: editor)

        await sut.saveChanges()

        #expect(sut.isSaving == false)
    }

    @Test
    func saveChanges_updatesEditor() async {
        let editor = SecureNoteDetailEditorMock()
        let sut = makeSUTEditing(editor: editor)

        await confirmation { confirmation in
            editor.updateNoteHandler = { _, _, _ in
                confirmation.confirm()
            }

            await sut.saveChanges()
        }
    }

    @Test
    func saveChanges_persistsEditingModelIfSuccessful() async {
        let sut = makeSUTEditing()
        makeDirty(sut: sut)

        await sut.saveChanges()

        #expect(sut.editingModel.isDirty == false)
    }

    @Test
    func saveChanges_locksItemWhenLockStateTurnsOn() async {
        let sut = makeSUTEditing(storedMetadata: anyVaultItemMetadata(lockState: .notLocked))
        sut.editingModel.detail.lockState = .lockedWithNativeSecurity

        await sut.saveChanges()

        #expect(sut.isLocked)
    }

    @Test
    func saveChanges_doesNotLockItemWhenLockStateStaysOff() async {
        let sut = makeSUTEditing(storedMetadata: anyVaultItemMetadata(lockState: .notLocked))
        makeDirty(sut: sut)

        await sut.saveChanges()

        #expect(sut.isLocked == false)
    }

    @Test
    func saveChanges_doesNotRelockUnlockedItemWhenLockStateStaysOn() async {
        let sut = makeSUTEditing(storedMetadata: anyVaultItemMetadata(lockState: .lockedWithNativeSecurity))
        sut.isLocked = false
        makeDirty(sut: sut)

        await sut.saveChanges()

        #expect(sut.isLocked == false)
    }

    @Test
    func saveChanges_doesNotLockItemIfSaveFailed() async {
        let editor = SecureNoteDetailEditorMock()
        editor.updateNoteHandler = { _, _, _ in
            throw TestError()
        }
        let sut = makeSUTEditing(storedMetadata: anyVaultItemMetadata(lockState: .notLocked), editor: editor)
        sut.editingModel.detail.lockState = .lockedWithNativeSecurity

        await sut.saveChanges()

        #expect(sut.isLocked == false)
    }

    @Test
    func saveChanges_setsSavingToFalseAfterSaveError() async {
        let editor = SecureNoteDetailEditorMock()
        editor.updateNoteHandler = { _, _, _ in
            throw TestError()
        }
        let sut = makeSUTEditing(editor: editor)

        await sut.saveChanges()

        #expect(sut.isSaving == false)
    }

    @Test
    func saveChanges_doesNotPersistEditingModelIfSaveFailed() async {
        let editor = SecureNoteDetailEditorMock()
        editor.updateNoteHandler = { _, _, _ in
            throw TestError()
        }
        let sut = makeSUTEditing(editor: editor)
        makeDirty(sut: sut)

        await sut.saveChanges()

        #expect(sut.editingModel.isDirty)
    }

    @Test
    func saveChanges_sendsErrorIfSaveError() async throws {
        let editor = SecureNoteDetailEditorMock()
        editor.updateNoteHandler = { _, _, _ in
            throw TestError()
        }
        let sut = makeSUTEditing(editor: editor)

        try await sut.didEncounterErrorPublisher().expect(valueCount: 1) {
            await sut.saveChanges()
        }
    }

    @Test
    func deleteNote_hasNoActionIfCreatingNote() async {
        let editor = SecureNoteDetailEditorMock()
        let sut = makeSUTCreating(editor: editor)

        await sut.deleteNote()

        editor.assertNoOperationsPerformed()
    }

    @Test
    func deleteNote_isSavingSetsBackToFalseAfterSuccessfulDelete() async {
        let sut = makeSUTEditing()

        await sut.deleteNote()

        #expect(sut.isSaving == false)
    }

    @Test
    func deleteNote_sendsFinishSignalOnSuccessfulDeletion() async throws {
        let sut = makeSUTEditing()

        try await sut.isFinishedPublisher().expect(valueCount: 1) {
            await sut.deleteNote()
        }
    }

    @Test
    func deleteNote_sendsErrorIfDeleteError() async throws {
        let editor = SecureNoteDetailEditorMock()
        editor.deleteNoteHandler = { _ in
            throw TestError()
        }
        let sut = makeSUTEditing(editor: editor)

        try await sut.didEncounterErrorPublisher().expect(valueCount: 1) {
            await sut.deleteNote()
        }
    }

    @Test
    func done_restoresInitialEditingStateIfInEditMode() {
        let sut = makeSUTEditing()
        sut.startEditing()
        makeDirty(sut: sut)

        sut.done()

        #expect(sut.editingModel.isDirty == false)
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
        var note = anySecureNote()
        note.contents = "first line\nsecond line"
        note.title = "this is my title"
        let metadata = anyVaultItemMetadata()
        let sut = makeSUTEditing(storedNote: note, storedMetadata: metadata)

        let editing = sut.editingModel

        #expect(editing.initialDetail.contents == note.contents)
        #expect(editing.initialDetail.titleLine == "first line")
    }

    @Test
    func editingModel_editingStateUsesData() {
        var note = anySecureNote()
        note.contents = "first line\nsecond line"
        note.title = "this is my title"
        var metadata = anyVaultItemMetadata()
        metadata.userDescription = "description test"
        let sut = makeSUTEditing(storedNote: note, storedMetadata: metadata)

        let editing = sut.editingModel

        #expect(editing.detail.contents == note.contents)
        #expect(editing.detail.titleLine == "first line")
    }

    @Test
    func shouldShowDeleteButton_falseForCreating() {
        let sut = makeSUTCreating()

        #expect(sut.shouldShowDeleteButton == false)
    }

    @Test
    func shouldShowDeleteButton_trueForEditing() {
        let sut = makeSUTEditing()

        #expect(sut.shouldShowDeleteButton)
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

    @Test
    func allTags_returnsDataModelTags() {
        let tags = [anyVaultItemTag(), anyVaultItemTag()]
        let dataModel = anyVaultDataModel()
        dataModel.allTags = tags

        let sut = makeSUT(dataModel: dataModel)

        #expect(sut.allTags == tags)
    }

    @Test
    func delete_callsDeleteWrapper() async {
        let editor = SecureNoteDetailEditorMock()
        let sut = makeSUTEditing(editor: editor)

        await sut.delete()

        #expect(editor.deleteNoteCallCount == 1)
    }

    @Test
    func dateValues_areNilWhenCreating() {
        let sut = makeSUTCreating()

        #expect(sut.createdDateValue == nil)
        #expect(sut.updatedDateValue == nil)
    }

    @Test
    func dateValues_includeCreatedAndSignificantUpdateWhenEditing() {
        let created = Date(timeIntervalSince1970: 100)
        let updated = created.addingTimeInterval(10)
        let metadata = VaultItem.Metadata(
            id: .new(),
            created: created,
            updated: updated,
            relativeOrder: 0,
            userDescription: "",
            tags: [],
            visibility: .always,
            searchableLevel: .full,
            searchPassphrase: nil,
            killphrase: nil,
            lockState: .notLocked,
            color: nil,
            showInQuickType: true,
            previewMode: .titleAndFirstLine,
        )
        let sut = makeSUTEditing(storedMetadata: metadata)

        #expect(sut.createdDateValue != nil)
        #expect(sut.updatedDateValue != nil)
    }

    @Test
    func dateValues_omitSmallUpdatedDateDelta() {
        let created = Date(timeIntervalSince1970: 100)
        let metadata = VaultItem.Metadata(
            id: .new(),
            created: created,
            updated: created.addingTimeInterval(5),
            relativeOrder: 0,
            userDescription: "",
            tags: [],
            visibility: .always,
            searchableLevel: .full,
            searchPassphrase: nil,
            killphrase: nil,
            lockState: .notLocked,
            color: nil,
            showInQuickType: true,
            previewMode: .titleAndFirstLine,
        )
        let sut = makeSUTEditing(storedMetadata: metadata)

        #expect(sut.updatedDateValue == nil)
    }

    @Test
    func detailEntries_includeDatesWhenAvailableAndVisibility() {
        let created = Date(timeIntervalSince1970: 100)
        let metadata = VaultItem.Metadata(
            id: .new(),
            created: created,
            updated: created.addingTimeInterval(10),
            relativeOrder: 0,
            userDescription: "",
            tags: [],
            visibility: .onlySearch,
            searchableLevel: .onlyPassphrase,
            searchPassphrase: nil,
            killphrase: nil,
            lockState: .notLocked,
            color: nil,
            showInQuickType: true,
            previewMode: .titleAndFirstLine,
        )
        let sut = makeSUTEditing(storedMetadata: metadata)

        let entries = sut.detailEntries

        #expect(entries.count == 3)
        #expect(entries.map(\.systemIconName) == ["clock", "clock.arrow.2.circlepath", "eye.slash"])
    }

    @Test
    func strings_areExposed() {
        let sut = makeSUTCreating()

        #expect(sut.strings.title.isEmpty == false)
        #expect(sut.strings.tagCount(tags: 2).isEmpty == false)
    }
}

extension SecureNoteDetailViewModelTests {
    @MainActor
    private func makeSUTEditing(
        storedNote: SecureNote = anySecureNote(),
        storedMetadata: VaultItem.Metadata = anyVaultItemMetadata(),
        existingKey: DerivedEncryptionKey? = nil,
        editor: SecureNoteDetailEditorMock = SecureNoteDetailEditorMock(),
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
    ) -> SecureNoteDetailViewModel {
        SecureNoteDetailViewModel(
            mode: .editing(note: storedNote, metadata: storedMetadata, existingKey: existingKey),
            dataModel: dataModel,
            editor: editor,
        )
    }

    @MainActor
    private func makeSUTCreating(
        editor: SecureNoteDetailEditorMock = SecureNoteDetailEditorMock(),
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
    ) -> SecureNoteDetailViewModel {
        SecureNoteDetailViewModel(mode: .creating(defaults: defaults), dataModel: dataModel, editor: editor)
    }

    @MainActor
    private func makeSUT(
        editor: SecureNoteDetailEditorMock = SecureNoteDetailEditorMock(),
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
    ) -> SecureNoteDetailViewModel {
        SecureNoteDetailViewModel(mode: .creating(defaults: NewItemDefaults()), dataModel: dataModel, editor: editor)
    }

    @MainActor
    private func makeDirty(sut: SecureNoteDetailViewModel, sourceLocation: SourceLocation = #_sourceLocation) {
        sut.editingModel.detail.contents = UUID().uuidString
        #expect(sut.editingModel.isDirty, sourceLocation: sourceLocation)
    }
}

extension SecureNoteDetailEditorMock {
    func assertNoOperationsPerformed(sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(createNoteCallCount == 0, sourceLocation: sourceLocation)
        #expect(updateNoteCallCount == 0, sourceLocation: sourceLocation)
        #expect(deleteNoteCallCount == 0, sourceLocation: sourceLocation)
    }
}
