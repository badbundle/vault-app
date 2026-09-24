import Foundation
import TestHelpers
import Testing
import VaultCore
import VaultKeygen
@testable import VaultFeed

@MainActor
struct RecoveryPhraseDetailViewModelTests {
    @Test
    func init_hasNoSideEffects() {
        let editor = RecoveryPhraseDetailEditorMock()
        _ = makeSUTCreating(editor: editor)
        _ = makeSUTEditing(editor: editor)

        editor.assertNoOperationsPerformed()
    }

    @Test
    func init_editingModelUsesInitialData() {
        let phrase = anyRecoveryPhrase(title: "Wallet", standard: .bip39, passphrase: " extra ")
        let key = anyKey()
        let metadata = anyVaultItemMetadata(color: .init(red: 0.1, green: 0.2, blue: 0.3), previewMode: .titleOnly)
        let sut = makeSUTEditing(phrase: phrase, metadata: metadata, key: key)

        let detail = sut.editingModel.detail
        #expect(detail.title == "Wallet")
        #expect(detail.words == phrase.words)
        #expect(detail.standard == .bip39)
        #expect(detail.seedPassphrase == " extra ")
        #expect(detail.existingEncryptionKey == key)
        #expect(detail.newEncryptionPassword == "")
        #expect(detail.color == metadata.color)
        #expect(detail.previewMode == .titleOnly)
        #expect(sut.editingModel.isDirty == false)
    }

    @Test
    func init_creatingStartsBlank() {
        let sut = makeSUTCreating()

        #expect(sut.editingModel.detail == .new())
        #expect(sut.isInitialCreation)
    }

    // MARK: - Locking

    @Test
    func isLocked_existingItemAlwaysStartsLocked() {
        // Even if the stored lock state somehow says otherwise.
        let sut = makeSUTEditing(metadata: anyVaultItemMetadata(lockState: .notLocked))

        #expect(sut.isLocked)
    }

    @Test
    func isLocked_creatingStartsUnlocked() {
        let sut = makeSUTCreating()

        #expect(sut.isLocked == false)
    }

    @Test
    func allowsUnlockWithoutDeviceAuthentication_isFalse() {
        #expect(makeSUTEditing().allowsUnlockWithoutDeviceAuthentication == false)
        #expect(makeSUTCreating().allowsUnlockWithoutDeviceAuthentication == false)
    }

    @Test
    func lock_locksUnlockedItem() {
        let sut = makeSUTEditing()
        sut.isLocked = false

        sut.lock()

        #expect(sut.isLocked)
    }

    // MARK: - Saving

    @Test
    func saveChanges_creatingCreatesAndFinishes() async throws {
        let editor = RecoveryPhraseDetailEditorMock()
        let sut = makeSUTCreating(editor: editor)

        try await sut.isFinishedPublisher().expect(valueCount: 1) {
            await sut.saveChanges()
        }

        #expect(editor.createRecoveryPhraseCallCount == 1)
    }

    @Test
    func saveChanges_creatingSendsErrorIfSaveError() async throws {
        let editor = RecoveryPhraseDetailEditorMock()
        editor.createRecoveryPhraseHandler = { _ in throw TestError() }
        let sut = makeSUTCreating(editor: editor)

        try await sut.didEncounterErrorPublisher().expect(valueCount: 1) {
            await sut.saveChanges()
        }
        #expect(sut.isSaving == false)
    }

    @Test
    func saveChanges_editingUpdatesWithEdits() async throws {
        let editor = RecoveryPhraseDetailEditorMock()
        let metadata = anyVaultItemMetadata()
        let key = anyKey()
        editor.updateRecoveryPhraseHandler = { _, _ in key }
        let sut = makeSUTEditing(metadata: metadata, key: key, editor: editor)
        sut.editingModel.detail.title = "New title"

        await sut.saveChanges()

        #expect(editor.updateRecoveryPhraseCallCount == 1)
        #expect(editor.updateRecoveryPhraseArgValues.first?.0 == metadata.id)
        #expect(editor.updateRecoveryPhraseArgValues.first?.1.title == "New title")
        #expect(sut.editingModel.isDirty == false)
    }

    @Test
    func saveChanges_keepsNewKeyAndDropsPasswordAfterSaving() async {
        let editor = RecoveryPhraseDetailEditorMock()
        let newKey = anyKey()
        editor.updateRecoveryPhraseHandler = { _, _ in newKey }
        let sut = makeSUTEditing(key: anyKey(), editor: editor)
        sut.editingModel.detail.newEncryptionPassword = "changed"

        await sut.saveChanges()

        #expect(sut.editingModel.detail.newEncryptionPassword == "")
        #expect(sut.editingModel.detail.existingEncryptionKey == newKey)
        #expect(sut.editingModel.isDirty == false)
    }

    @Test
    func saveChanges_editingFailureKeepsEditsAndSendsError() async throws {
        let editor = RecoveryPhraseDetailEditorMock()
        editor.updateRecoveryPhraseHandler = { _, _ in throw TestError() }
        let sut = makeSUTEditing(editor: editor)
        sut.editingModel.detail.newEncryptionPassword = "changed"

        try await sut.didEncounterErrorPublisher().expect(valueCount: 1) {
            await sut.saveChanges()
        }

        #expect(sut.editingModel.isDirty)
        #expect(sut.editingModel.detail.newEncryptionPassword == "changed")
    }

    // MARK: - Deleting

    @Test
    func delete_hasNoActionWhenCreating() async {
        let editor = RecoveryPhraseDetailEditorMock()
        let sut = makeSUTCreating(editor: editor)

        await sut.delete()

        editor.assertNoOperationsPerformed()
    }

    @Test
    func delete_deletesAndFinishes() async throws {
        let editor = RecoveryPhraseDetailEditorMock()
        let metadata = anyVaultItemMetadata()
        let sut = makeSUTEditing(metadata: metadata, editor: editor)

        try await sut.isFinishedPublisher().expect(valueCount: 1) {
            await sut.delete()
        }

        #expect(editor.deleteRecoveryPhraseArgValues == [metadata.id])
    }

    @Test
    func delete_sendsErrorIfDeleteError() async throws {
        let editor = RecoveryPhraseDetailEditorMock()
        editor.deleteRecoveryPhraseHandler = { _ in throw TestError() }
        let sut = makeSUTEditing(editor: editor)

        try await sut.didEncounterErrorPublisher().expect(valueCount: 1) {
            await sut.delete()
        }
    }

    @Test
    func done_restoresInitialStateInEditMode() {
        let sut = makeSUTEditing()
        sut.startEditing()
        sut.editingModel.detail.title = "changed"

        sut.done()

        #expect(sut.editingModel.isDirty == false)
        #expect(sut.isInEditMode == false)
    }

    // MARK: - Suggestions

    @Test
    func suggestions_completesFromWordlist() {
        let sut = makeSUTCreating()
        sut.editingModel.detail.applyInput("ab", at: 0)

        #expect(sut.suggestions(forWordAt: 0) == ["abandon", "ability", "able"])
    }

    @Test
    func suggestions_emptyForBlankWordOrExactMatch() {
        let sut = makeSUTCreating()

        #expect(sut.suggestions(forWordAt: 0).isEmpty)
        sut.editingModel.detail.applyInput("zoo", at: 0)
        #expect(sut.suggestions(forWordAt: 0).isEmpty)
    }

    @Test
    func suggestions_emptyForOutOfRangeWord() {
        let sut = makeSUTCreating()

        #expect(sut.suggestions(forWordAt: 99).isEmpty)
    }

    @Test
    func suggestions_prefersDeviceLanguage() {
        let sut = makeSUTCreating(locale: Locale(identifier: "es_ES"))
        sut.editingModel.detail.applyInput("arb", at: 0)

        #expect(sut.suggestions(forWordAt: 0) == ["árbitro", "árbol", "arbusto"])
    }

    @Test
    func suggestions_followsLanguageOfOtherWords() {
        let sut = makeSUTCreating(locale: Locale(identifier: "en_US"))
        // "árbol" is only in the Spanish list, so suggestions come from it.
        sut.editingModel.detail.applyInput("árbol", at: 0)
        sut.editingModel.detail.applyInput("aba", at: 1)

        #expect(sut.suggestions(forWordAt: 1) == ["ábaco"])
    }

    @Test
    func suggestions_noneForOtherStandard() {
        let sut = makeSUTCreating()
        sut.editingModel.detail.setStandard(.other)
        sut.editingModel.detail.applyInput("ab", at: 0)

        #expect(sut.suggestions(forWordAt: 0).isEmpty)
    }

    // MARK: - Validation summary

    @Test
    func validationSummary_validPhrase() {
        let sut = makeSUTEditing(phrase: anyRecoveryPhrase())

        let summary = sut.validationSummary()

        #expect(summary.kind == .valid)
        #expect(summary.title == "Valid BIP39 phrase")
        #expect(summary.detail == "English · 12 words")
    }

    @Test
    func validationSummary_wordBeingEditedIsNotReportedUnknown() {
        let sut = makeSUTCreating()
        sut.editingModel.detail.applyInput("aba", at: 0)

        #expect(sut.validationSummary().unknownWordPositions == [0])
        #expect(sut.validationSummary(whileEditingWordAt: 0).unknownWordPositions.isEmpty)
        #expect(sut.validationSummary(whileEditingWordAt: 0).kind == .neutral)
    }

    @Test
    func visibleTitle_usesPlaceholderWhenBlank() {
        #expect(makeSUTEditing(phrase: anyRecoveryPhrase(title: "  ")).visibleTitle == "Untitled")
        #expect(makeSUTEditing(phrase: anyRecoveryPhrase(title: "Mine")).visibleTitle == "Mine")
    }
}

// MARK: - Helpers

extension RecoveryPhraseDetailViewModelTests {
    private func makeSUTEditing(
        phrase: RecoveryPhrase = anyRecoveryPhrase(),
        metadata: VaultItem.Metadata = anyVaultItemMetadata(lockState: .lockedWithNativeSecurity),
        key: DerivedEncryptionKey? = nil,
        editor: RecoveryPhraseDetailEditorMock = RecoveryPhraseDetailEditorMock(),
    ) -> RecoveryPhraseDetailViewModel {
        RecoveryPhraseDetailViewModel(
            mode: .editing(phrase: phrase, metadata: metadata, existingKey: key ?? anyKey()),
            dataModel: anyVaultDataModel(),
            editor: editor,
        )
    }

    private func makeSUTCreating(
        editor: RecoveryPhraseDetailEditorMock = RecoveryPhraseDetailEditorMock(),
        locale: Locale = Locale(identifier: "en_US"),
    ) -> RecoveryPhraseDetailViewModel {
        RecoveryPhraseDetailViewModel(mode: .creating, dataModel: anyVaultDataModel(), editor: editor, locale: locale)
    }

    private func anyKey() -> DerivedEncryptionKey {
        DerivedEncryptionKey(key: .random(), salt: .random(count: 32), keyDervier: .testing)
    }
}

extension RecoveryPhraseDetailEditorMock {
    func assertNoOperationsPerformed(sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(createRecoveryPhraseCallCount == 0, sourceLocation: sourceLocation)
        #expect(updateRecoveryPhraseCallCount == 0, sourceLocation: sourceLocation)
        #expect(deleteRecoveryPhraseCallCount == 0, sourceLocation: sourceLocation)
    }
}
