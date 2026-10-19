import Foundation
import TestHelpers
import Testing
import VaultCore
import VaultKeygen
@testable import VaultFeed

@MainActor
struct PrivateKeyDetailViewModelTests {
    @Test
    func init_hasNoSideEffects() {
        let editor = PrivateKeyDetailEditorMock()
        _ = makeSUTCreating(editor: editor)
        _ = makeSUTEditing(editor: editor)

        editor.assertNoOperationsPerformed()
    }

    @Test
    func init_editingModelUsesInitialData() {
        let privateKey = anyPrivateKey(title: "Wallet", key: validWIFKey, contents: "Context")
        let key = anyKey()
        let metadata = anyVaultItemMetadata(color: .init(red: 0.1, green: 0.2, blue: 0.3), previewMode: .titleOnly)
        let sut = makeSUTEditing(privateKey: privateKey, metadata: metadata, key: key)

        let detail = sut.editingModel.detail
        #expect(detail.title == "Wallet")
        #expect(detail.contents == "Context")
        #expect(detail.key == validWIFKey)
        #expect(detail.existingEncryptionKey == key)
        #expect(detail.newEncryptionPassword == "")
        #expect(detail.color == metadata.color)
        #expect(detail.previewMode == .titleOnly)
        #expect(detail.lockState == .lockedWithNativeSecurity)
        #expect(sut.editingModel.isDirty == false)
    }

    @Test
    func init_creatingStartsBlank() {
        let sut = makeSUTCreating()

        #expect(sut.editingModel.detail == .new())
        #expect(sut.isInitialCreation)
    }

    // MARK: - Locking

    /// Always locked, whatever its stored lock state says (G102).
    @Test
    func isLocked_existingItemAlwaysStartsLocked() {
        let sut = makeSUTEditing(metadata: anyVaultItemMetadata(lockState: .notLocked))

        #expect(sut.isLocked)
    }

    @Test
    func isLocked_creatingStartsUnlocked() {
        #expect(makeSUTCreating().isLocked == false)
    }

    /// A device without a passcode can't skip the lock: device authentication is always needed.
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

    // MARK: - Masking

    /// Masked until tapped, even once it's unlocked (G103).
    @Test
    func isKeyRevealed_existingItemStartsMasked() {
        #expect(makeSUTEditing().isKeyRevealed == false)
    }

    @Test
    func isKeyRevealed_creatingStartsRevealed() {
        #expect(makeSUTCreating().isKeyRevealed)
    }

    @Test
    func lock_masksARevealedKey() {
        let sut = makeSUTEditing()
        sut.isLocked = false
        sut.isKeyRevealed = true

        sut.lock()

        #expect(sut.isKeyRevealed == false)
    }

    @Test
    func isKeyRevealed_doesNotMakeEditsDirty() {
        let sut = makeSUTEditing()

        sut.isKeyRevealed = true

        #expect(sut.editingModel.isDirty == false)
    }

    // MARK: - The editor's overview

    /// The overview is on screen for anyone to see, so it names the kind of key, never the key or its description.
    @Test
    func editorSummary_neverIncludesTheKeyOrItsDescription() {
        let sut = makeSUTEditing(privateKey: anyPrivateKey(title: "Title", key: validWIFKey, contents: "Secret note"))

        for step in DetailEditorStep.allCases {
            let summary = sut.editorSummary(for: step)
            #expect(!summary.contains(validWIFKey.prefix(6)))
            #expect(!summary.contains("Secret"))
        }
        #expect(sut.editorSummary(for: .content) == "WIF")
        #expect(sut.editorSummary(for: .details) == "Title")
    }

    @Test
    func editorSummary_anyOtherTextIsOther() {
        let sut = makeSUTEditing(privateKey: anyPrivateKey(key: "some text"))

        #expect(sut.editorSummary(for: .content) == "Other")
    }

    // MARK: - Saving

    @Test
    func saveChanges_creatingCreatesAndFinishes() async throws {
        let editor = PrivateKeyDetailEditorMock()
        let sut = makeSUTCreating(editor: editor)

        try await sut.isFinishedPublisher().expect(valueCount: 1) {
            await sut.saveChanges()
        }

        #expect(editor.createPrivateKeyCallCount == 1)
    }

    @Test
    func saveChanges_creatingSendsErrorIfSaveError() async throws {
        let editor = PrivateKeyDetailEditorMock()
        editor.createPrivateKeyHandler = { _ in throw TestError() }
        let sut = makeSUTCreating(editor: editor)

        try await sut.didEncounterErrorPublisher().expect(valueCount: 1) {
            await sut.saveChanges()
        }
        #expect(sut.isSaving == false)
    }

    @Test
    func saveChanges_editingUpdatesWithEdits() async throws {
        let editor = PrivateKeyDetailEditorMock()
        let metadata = anyVaultItemMetadata()
        let key = anyKey()
        editor.updatePrivateKeyHandler = { _, _ in key }
        let sut = makeSUTEditing(metadata: metadata, key: key, editor: editor)
        sut.editingModel.detail.title = "New title"

        await sut.saveChanges()

        #expect(editor.updatePrivateKeyCallCount == 1)
        #expect(editor.updatePrivateKeyArgValues.first?.0 == metadata.id)
        #expect(editor.updatePrivateKeyArgValues.first?.1.title == "New title")
        #expect(sut.editingModel.isDirty == false)
    }

    /// Keeps the derived key, not the password, so the password isn't kept in memory (G42).
    @Test
    func saveChanges_keepsNewKeyAndDropsPasswordAfterSaving() async {
        let editor = PrivateKeyDetailEditorMock()
        let newKey = anyKey()
        editor.updatePrivateKeyHandler = { _, _ in newKey }
        let sut = makeSUTEditing(key: anyKey(), editor: editor)
        sut.editingModel.detail.newEncryptionPassword = "changed"

        await sut.saveChanges()

        #expect(sut.editingModel.detail.newEncryptionPassword == "")
        #expect(sut.editingModel.detail.existingEncryptionKey == newKey)
        #expect(sut.editingModel.isDirty == false)
    }

    @Test
    func saveChanges_editingFailureKeepsEditsAndSendsError() async throws {
        let editor = PrivateKeyDetailEditorMock()
        editor.updatePrivateKeyHandler = { _, _ in throw TestError() }
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
        let editor = PrivateKeyDetailEditorMock()
        let sut = makeSUTCreating(editor: editor)

        await sut.delete()

        editor.assertNoOperationsPerformed()
    }

    @Test
    func delete_deletesAndFinishes() async throws {
        let editor = PrivateKeyDetailEditorMock()
        let metadata = anyVaultItemMetadata()
        let sut = makeSUTEditing(metadata: metadata, editor: editor)

        try await sut.isFinishedPublisher().expect(valueCount: 1) {
            await sut.delete()
        }

        #expect(editor.deletePrivateKeyArgValues == [metadata.id])
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

    // MARK: - Validation

    @Test
    func validationSummary_validKeyShowsItsFormat() {
        let sut = makeSUTEditing(privateKey: anyPrivateKey(key: validWIFKey))

        let summary = sut.validationSummary()

        #expect(summary.kind == .valid)
        #expect(summary.title == "Valid private key")
        #expect(summary.detail == "WIF · mainnet · compressed")
    }

    @Test
    func validationSummary_followsTheKeyAsItsTyped() {
        let sut = makeSUTCreating()
        #expect(sut.validationSummary().kind == .neutral)

        sut.editingModel.detail.key = String(validWIFKey.dropLast()) + "8"
        #expect(sut.validationSummary().title == "Checksum doesn't match")

        sut.editingModel.detail.key = validWIFKey
        #expect(sut.validationSummary().kind == .valid)
    }

    @Test
    func visibleTitle_usesPlaceholderWhenBlank() {
        #expect(makeSUTEditing(privateKey: anyPrivateKey(title: "  ")).visibleTitle == "Untitled")
        #expect(makeSUTEditing(privateKey: anyPrivateKey(title: "Mine")).visibleTitle == "Mine")
    }
}

// MARK: - Helpers

extension PrivateKeyDetailViewModelTests {
    private func makeSUTEditing(
        privateKey: PrivateKey = anyPrivateKey(),
        metadata: VaultItem.Metadata = anyVaultItemMetadata(lockState: .lockedWithNativeSecurity),
        key: DerivedEncryptionKey? = nil,
        editor: PrivateKeyDetailEditorMock = PrivateKeyDetailEditorMock(),
    ) -> PrivateKeyDetailViewModel {
        PrivateKeyDetailViewModel(
            mode: .editing(key: privateKey, metadata: metadata, existingKey: key ?? anyKey()),
            dataModel: anyVaultDataModel(),
            editor: editor,
        )
    }

    private func makeSUTCreating(
        editor: PrivateKeyDetailEditorMock = PrivateKeyDetailEditorMock(),
    ) -> PrivateKeyDetailViewModel {
        PrivateKeyDetailViewModel(mode: .creating, dataModel: anyVaultDataModel(), editor: editor)
    }

    private func anyKey() -> DerivedEncryptionKey {
        DerivedEncryptionKey(key: .random(), salt: .random(count: 32), keyDervier: .testing)
    }
}

extension PrivateKeyDetailEditorMock {
    func assertNoOperationsPerformed(sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(createPrivateKeyCallCount == 0, sourceLocation: sourceLocation)
        #expect(updatePrivateKeyCallCount == 0, sourceLocation: sourceLocation)
        #expect(deletePrivateKeyCallCount == 0, sourceLocation: sourceLocation)
    }
}
