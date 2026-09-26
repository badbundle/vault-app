import Foundation
import FoundationExtensions
import TestHelpers
import Testing
import VaultCore
import VaultFeed
import VaultKeygen

/// How each kind of item's view model lays out and moves through its editor.
@MainActor
struct DetailViewModelEditorTests {
    // MARK: - Codes

    @Test
    func code_creatingWalksThroughEveryStepFromTheKey() {
        let sut = makeCodeCreating()

        #expect(sut.editorFlow.style == .guided)
        #expect(sut.editorFlow.steps == [.content, .details, .appearance, .security])
        #expect(sut.editorFlow.currentStep == .content)
    }

    @Test
    func code_creatingWithCodeStartsOnNamingIt() {
        let sut = makeCodeCreating(initialCode: anyOTPAuthCode(issuerName: "Site"))

        #expect(sut.editorFlow.style == .guided)
        #expect(sut.editorFlow.currentStep == .details)
    }

    @Test
    func code_editingOpensOnOverviewWithoutTheKey() {
        let sut = makeCodeEditing()

        sut.startEditing()

        #expect(sut.editorFlow.style == .overview)
        #expect(sut.editorFlow.steps == [.details, .appearance, .security])
        #expect(sut.editorFlow.isShowingOverview)
    }

    @Test
    func code_startEditingResetsTheEditor() {
        let sut = makeCodeEditing()
        sut.startEditing()
        sut.showEditorStep(.security)

        sut.startEditing()

        #expect(sut.editorFlow.isShowingOverview)
    }

    @Test
    func code_continueInEditorNeedsTheStepComplete() {
        let sut = makeCodeCreating()

        sut.continueInEditor()
        #expect(sut.editorFlow.currentStep == .content)
        #expect(sut.canContinueInEditor == false)

        sut.editingModel.detail.secretBase32String = "JBSWY3DPEHPK3PXP"
        #expect(sut.canContinueInEditor)
        sut.continueInEditor()
        #expect(sut.editorFlow.currentStep == .details)

        sut.continueInEditor()
        #expect(sut.editorFlow.currentStep == .details, "The site name is required")

        sut.editingModel.detail.issuerTitle = "Site"
        sut.continueInEditor()
        #expect(sut.editorFlow.currentStep == .appearance)
    }

    @Test
    func code_goBackInEditorReturnsToPreviousStep() {
        let sut = makeCodeCreating()
        sut.editingModel.detail.secretBase32String = "JBSWY3DPEHPK3PXP"
        sut.continueInEditor()

        sut.goBackInEditor()

        #expect(sut.editorFlow.currentStep == .content)
    }

    @Test
    func code_showEditorStepCannotSkipIncompleteSteps() {
        let sut = makeCodeCreating()

        sut.showEditorStep(.security)

        #expect(sut.editorFlow.currentStep == .content)
    }

    @Test
    func code_showEditorStepOpensAnyStepFromOverview() {
        let sut = makeCodeEditing()
        sut.startEditing()

        sut.showEditorStep(.security)

        #expect(sut.editorFlow.currentStep == .security)
    }

    @Test
    func code_applyScannedCodeFillsKeyAndNamesAndMovesOn() {
        let sut = makeCodeCreating()
        sut.editingModel.detail.description = "Kept"
        let code = OTPAuthCode(
            type: .hotp(counter: 7),
            data: .init(
                secret: .init(data: Data(hex: "afafafaf"), format: .base32),
                algorithm: .sha256,
                digits: .init(value: 8),
                accountName: "me@example.com",
                issuer: "Example",
            ),
        )

        sut.applyScannedCode(code)

        let detail = sut.editingModel.detail
        #expect(detail.codeType == .hotp)
        #expect(detail.hotpCounterValue == 7)
        #expect(detail.algorithm == .sha256)
        #expect(detail.numberOfDigits == 8)
        #expect(detail.secretBase32String == code.data.secret.base32EncodedString)
        #expect(detail.issuerTitle == "Example")
        #expect(detail.accountNameTitle == "me@example.com")
        #expect(detail.description == "Kept")
        #expect(sut.editorFlow.currentStep == .details)
    }

    @Test
    func code_applyScannedCodeKeepsNamesTheCodeDoesNotHave() {
        let sut = makeCodeCreating()
        sut.editingModel.detail.issuerTitle = "Typed"
        sut.editingModel.detail.accountNameTitle = "Typed Account"

        sut.applyScannedCode(anyOTPAuthCode())

        #expect(sut.editingModel.detail.issuerTitle == "Typed")
        #expect(sut.editingModel.detail.accountNameTitle == "Typed Account")
    }

    @Test
    func code_editorSummary() {
        let sut = makeCodeEditing(
            code: anyOTPAuthCode(accountName: "me@example.com", issuerName: "Example"),
            metadata: anyVaultItemMetadata(lockState: .lockedWithNativeSecurity),
        )

        #expect(sut.editorSummary(for: .details) == "Example · me@example.com")
        #expect(sut.editorSummary(for: .appearance) == "No Tags")
        #expect(sut.editorSummary(for: .security) == "Always visible · Locked")
    }

    @Test
    func code_editorSummaryListsAttachedTags() async throws {
        let tagStore = VaultTagStoreStub()
        let work = anyVaultItemTag(name: "Work")
        let home = anyVaultItemTag(name: "Home")
        tagStore.retrieveTagsHandler = { [work, home] }
        let dataModel = anyVaultDataModel(vaultTagStore: tagStore)
        await dataModel.reloadTags()
        let sut = makeCodeEditing(
            metadata: anyVaultItemMetadata(tags: [work.id]),
            dataModel: dataModel,
        )

        #expect(sut.editorSummary(for: .appearance) == "Work")
    }

    @Test
    func code_editorSummaryNeverMentionsKillphrase() {
        let sut = makeCodeEditing()
        sut.editingModel.detail.killphraseEnabled = true

        #expect(sut.editorSummary(for: .security).localizedCaseInsensitiveContains("kill") == false)
    }

    // MARK: - Notes

    @Test
    func note_hasNoDetailsStep() {
        let creating = makeNoteCreating()
        let editing = makeNoteEditing()

        #expect(creating.editorFlow.steps == [.content, .appearance, .security])
        #expect(creating.editorFlow.style == .guided)
        #expect(creating.editorFlow.currentStep == .content)
        #expect(editing.editorFlow.steps == [.content, .appearance, .security])
        #expect(editing.editorFlow.style == .overview)
    }

    @Test
    func note_securityStepNeedsPassphraseWhenHidden() {
        let sut = makeNoteCreating()
        sut.continueInEditor()
        sut.continueInEditor()
        #expect(sut.editorFlow.currentStep == .security)

        sut.editingModel.detail.viewConfig = .requiresSearchPassphrase
        #expect(sut.isEditorStepComplete(.security) == false)
        #expect(sut.editingModel.isValid == false)

        sut.editingModel.detail.searchPassphrase = "hidden"
        #expect(sut.isEditorStepComplete(.security))
        #expect(sut.editingModel.isValid)
    }

    @Test
    func note_blankKillphraseMakesItInvalid() {
        let sut = makeNoteCreating()
        sut.editingModel.detail.killphraseEnabled = true
        sut.editingModel.detail.newKillphrase = "   "

        #expect(sut.isEditorStepComplete(.security) == false)
        #expect(sut.editingModel.isValid == false)
    }

    @Test
    func note_editorSummary() {
        let sut = makeNoteEditing(note: anySecureNote(contents: "Wi-Fi\nGuest network", format: .markdown))

        #expect(sut.editorSummary(for: .content) == "Wi-Fi · Markdown")
        #expect(sut.editorSummary(for: .security) == "Always visible · Not Locked")
    }

    // MARK: - Recovery phrases

    @Test
    func recoveryPhrase_hasEveryStep() {
        let creating = makePhraseCreating()
        let editing = makePhraseEditing()

        #expect(creating.editorFlow.steps == DetailEditorStep.allCases)
        #expect(creating.editorFlow.style == .guided)
        #expect(editing.editorFlow.steps == DetailEditorStep.allCases)
        #expect(editing.editorFlow.style == .overview)
    }

    @Test
    func recoveryPhrase_wordsStepNeedsEveryWord() {
        let sut = makePhraseCreating()

        #expect(sut.canContinueInEditor == false)

        sut.editingModel.detail.setWordCount(12)
        for (index, word) in validBIP39Words.dropLast().enumerated() {
            sut.editingModel.detail.applyInput(word, at: index)
        }
        #expect(sut.canContinueInEditor == false)

        sut.editingModel.detail.applyInput("about", at: 11)
        #expect(sut.canContinueInEditor)
    }

    @Test
    func recoveryPhrase_securityStepNeedsPassword() {
        let sut = makePhraseCreating()

        #expect(sut.isEditorStepComplete(.security) == false)

        sut.editingModel.detail.newEncryptionPassword = "password"
        #expect(sut.isEditorStepComplete(.security))
    }

    @Test
    func recoveryPhrase_editorSummaryNeverShowsSecrets() {
        let phrase = anyRecoveryPhrase(title: "Savings", passphrase: "extra words", contents: "In the safe")
        let sut = makePhraseEditing(phrase: phrase)
        let summaries = DetailEditorStep.allCases.map(sut.editorSummary(for:)).joined(separator: " ")

        #expect(summaries.contains("Savings"))
        #expect(summaries.contains("abandon") == false)
        #expect(summaries.contains("extra words") == false)
        #expect(summaries.contains("In the safe") == false)
    }

    @Test
    func recoveryPhrase_editorSummary() {
        let sut = makePhraseEditing(phrase: anyRecoveryPhrase(title: "Savings"))

        #expect(sut.editorSummary(for: .content) == "BIP39 · 12 words")
        #expect(sut.editorSummary(for: .details) == "Savings")
        #expect(sut.editorSummary(for: .security) == "Always visible · Encrypted")
    }
}

// MARK: - Helpers

extension DetailViewModelEditorTests {
    private func makeCodeCreating(initialCode: OTPAuthCode? = nil) -> OTPCodeDetailViewModel {
        OTPCodeDetailViewModel(
            mode: .creating(initialCode: initialCode, defaults: NewItemDefaults()),
            dataModel: anyVaultDataModel(),
            editor: OTPCodeDetailEditorMock(),
        )
    }

    private func makeCodeEditing(
        code: OTPAuthCode = anyOTPAuthCode(),
        metadata: VaultItem.Metadata = anyVaultItemMetadata(),
        dataModel: VaultDataModel? = nil,
    ) -> OTPCodeDetailViewModel {
        OTPCodeDetailViewModel(
            mode: .editing(code: code, metadata: metadata),
            dataModel: dataModel ?? anyVaultDataModel(),
            editor: OTPCodeDetailEditorMock(),
        )
    }

    private func makeNoteCreating() -> SecureNoteDetailViewModel {
        SecureNoteDetailViewModel(
            mode: .creating(defaults: NewItemDefaults()),
            dataModel: anyVaultDataModel(),
            editor: SecureNoteDetailEditorMock(),
        )
    }

    private func makeNoteEditing(note: SecureNote = anySecureNote()) -> SecureNoteDetailViewModel {
        SecureNoteDetailViewModel(
            mode: .editing(note: note, metadata: anyVaultItemMetadata(), existingKey: nil),
            dataModel: anyVaultDataModel(),
            editor: SecureNoteDetailEditorMock(),
        )
    }

    private func makePhraseCreating() -> RecoveryPhraseDetailViewModel {
        RecoveryPhraseDetailViewModel(
            mode: .creating,
            dataModel: anyVaultDataModel(),
            editor: RecoveryPhraseDetailEditorMock(),
        )
    }

    private func makePhraseEditing(phrase: RecoveryPhrase = anyRecoveryPhrase()) -> RecoveryPhraseDetailViewModel {
        RecoveryPhraseDetailViewModel(
            mode: .editing(
                phrase: phrase,
                metadata: anyVaultItemMetadata(lockState: .lockedWithNativeSecurity),
                existingKey: DerivedEncryptionKey(key: .random(), salt: .random(count: 32), keyDervier: .testing),
            ),
            dataModel: anyVaultDataModel(),
            editor: RecoveryPhraseDetailEditorMock(),
        )
    }
}
