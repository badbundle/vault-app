import Foundation
import SwiftUI
import TestHelpers
import Testing
import VaultFeed
@testable import VaultiOS

@MainActor
final class RecoveryPhraseDetailViewSnapshotTests {
    @Test
    func lockedState() {
        let sut = makeSUT(viewModel: makeEditingViewModel())

        snapshotScenarios(view: sut)
    }

    @Test
    func lockedStateNoAuthentication() {
        let sut = makeSUT(viewModel: makeEditingViewModel())

        snapshotScenarios(view: sut, deviceAuthenticationPolicy: .cannotAuthenticate)
    }

    @Test
    func valid24Words_masked() {
        let viewModel = makeEditingViewModel(phrase: .init(
            title: "Hardware wallet",
            words: bip39Valid24Words,
            standard: .bip39,
            passphrase: "",
            contents: "Kept in the safe at home. Long-term savings, don't touch.",
        ))
        viewModel.isLocked = false

        snapshotScenarios(view: makeSUT(viewModel: viewModel))
    }

    @Test
    func valid24Words_revealed() {
        let viewModel = makeEditingViewModel(phrase: .init(
            title: "Hardware wallet",
            words: bip39Valid24Words,
            standard: .bip39,
            passphrase: "",
            contents: "Kept in the safe at home. Long-term savings, don't touch.",
        ))
        viewModel.isLocked = false

        snapshotScenarios(view: makeSUT(viewModel: viewModel), beforeEach: { viewModel.areWordsRevealed = true })
    }

    @Test
    func invalidChecksum_revealed() {
        var words = bip39Valid24Words
        words.swapAt(0, 23)
        let viewModel = makeEditingViewModel(phrase: .init(
            title: "Hardware wallet",
            words: words,
            standard: .bip39,
            passphrase: "",
        ))
        viewModel.isLocked = false

        snapshotScenarios(
            view: makeSUT(viewModel: viewModel),
            dynamicTypeSizes: [.medium],
            beforeEach: { viewModel.areWordsRevealed = true },
        )
    }

    @Test
    func unknownWords_masked() {
        let viewModel = makeEditingViewModel(phrase: phraseWithUnknownWords)
        viewModel.isLocked = false

        snapshotScenarios(view: makeSUT(viewModel: viewModel), dynamicTypeSizes: [.medium])
    }

    @Test
    func unknownWords_revealed() {
        let viewModel = makeEditingViewModel(phrase: phraseWithUnknownWords)
        viewModel.isLocked = false

        snapshotScenarios(
            view: makeSUT(viewModel: viewModel),
            dynamicTypeSizes: [.medium],
            beforeEach: { viewModel.areWordsRevealed = true },
        )
    }

    @Test
    func maskedPassphrase() {
        let viewModel = makeEditingViewModel(phrase: .init(
            title: "",
            words: Array(repeating: "abandon", count: 11) + ["about"],
            standard: .bip39,
            passphrase: "my passphrase",
        ))
        viewModel.isLocked = false

        snapshotScenarios(view: makeSUT(viewModel: viewModel), dynamicTypeSizes: [.medium])
    }

    @Test
    func slip39Share_revealed() {
        let viewModel = makeEditingViewModel(phrase: .init(
            title: "Share 1",
            words: slip39ShareWords,
            standard: .slip39,
            passphrase: "",
        ))
        viewModel.isLocked = false

        snapshotScenarios(
            view: makeSUT(viewModel: viewModel),
            dynamicTypeSizes: [.medium, .accessibility2],
            beforeEach: { viewModel.areWordsRevealed = true },
        )
    }

    @Test
    func hiddenWhileInactive() {
        let viewModel = makeEditingViewModel()
        viewModel.isLocked = false

        snapshotScenarios(view: makeSUT(viewModel: viewModel), scenePhase: .inactive, dynamicTypeSizes: [.medium])
    }

    @Test
    func hiddenWhileCaptured() {
        let viewModel = makeEditingViewModel()
        viewModel.isLocked = false

        let sut = makeSUT(viewModel: viewModel)
            .environment(\.isSceneCaptured, true)

        snapshotScenarios(view: sut, dynamicTypeSizes: [.medium])
    }

    @Test
    func editMode_newPhrase() {
        let viewModel = makeCreatingViewModel()
        viewModel.editingModel.detail.setWordCount(12)

        snapshotScenarios(view: makeSUT(viewModel: viewModel), height: 2600)
    }

    @Test
    func editMode_unknownWord() {
        let viewModel = makeCreatingViewModel()
        viewModel.editingModel.detail.title = "Savings"
        viewModel.editingModel.detail.applyInput(
            "abandon abandon abandom abandon abandon abandon abandon abandon abandon abandon abandon about",
            at: 0,
        )
        viewModel.editingModel.detail.newEncryptionPassword = "password"

        snapshotScenarios(view: makeSUT(viewModel: viewModel), dynamicTypeSizes: [.medium], height: 1800)
    }

    @Test
    func editMode_existingPhraseMasked() {
        let viewModel = makeEditingViewModel(phrase: phraseWithUnknownWords)
        viewModel.isLocked = false
        viewModel.startEditing()
        viewModel.showEditorStep(.content)

        snapshotScenarios(view: makeSUT(viewModel: viewModel), dynamicTypeSizes: [.medium], height: 1800)
    }
}

// MARK: - Helpers

extension RecoveryPhraseDetailViewSnapshotTests {
    private func makeSUT(viewModel: RecoveryPhraseDetailViewModel) -> some View {
        RecoveryPhraseDetailView(viewModel: viewModel, navigationPath: .constant(NavigationPath()))
    }

    private func makeEditingViewModel(
        phrase: RecoveryPhrase = .init(
            title: "Wallet",
            words: Array(repeating: "abandon", count: 11) + ["about"],
            standard: .bip39,
            passphrase: "",
        ),
    ) -> RecoveryPhraseDetailViewModel {
        RecoveryPhraseDetailViewModel(
            mode: .editing(
                phrase: phrase,
                metadata: .init(
                    id: .new(),
                    created: fixedTestDate(),
                    updated: fixedTestDate(),
                    relativeOrder: .min,
                    userDescription: "",
                    tags: [],
                    visibility: .always,
                    searchableLevel: .full,
                    searchPassphrase: nil,
                    killphrase: nil,
                    lockState: .lockedWithNativeSecurity,
                    color: nil,
                    showInQuickType: false,
                    previewMode: .hidden,
                ),
                existingKey: .init(key: .zero(), salt: Data(), keyDervier: .testing),
            ),
            dataModel: anyVaultDataModel(),
            editor: RecoveryPhraseDetailEditorMock(),
            locale: Locale(identifier: "en_US"),
        )
    }

    private func makeCreatingViewModel() -> RecoveryPhraseDetailViewModel {
        let viewModel = RecoveryPhraseDetailViewModel(
            mode: .creating,
            dataModel: anyVaultDataModel(),
            editor: RecoveryPhraseDetailEditorMock(),
            locale: Locale(identifier: "en_US"),
        )
        viewModel.startEditing()
        return viewModel
    }

    private func snapshotScenarios(
        view: some View,
        deviceAuthenticationPolicy: some DeviceAuthenticationPolicy = DeviceAuthenticationPolicyAlwaysAllow(),
        scenePhase: ScenePhase = .active,
        dynamicTypeSizes: [DynamicTypeSize] = [.xSmall, .medium, .xxLarge],
        height: CGFloat = 1400,
        testName: String = #function,
        beforeEach: () -> Void = {},
    ) {
        let colorSchemes: [ColorScheme] = [.light, .dark]
        for colorScheme in colorSchemes {
            for dynamicTypeSize in dynamicTypeSizes {
                // The view masks the words again when it disappears, which it does after each snapshot.
                beforeEach()
                let snapshottingView = view
                    .environment(\.scenePhase, scenePhase)
                    .dynamicTypeSize(dynamicTypeSize)
                    .preferredColorScheme(colorScheme)
                    .framedForTest(height: height)
                    .environment(DeviceAuthenticationService(policy: deviceAuthenticationPolicy))
                let named = "\(colorScheme)_\(dynamicTypeSize)"

                assertSnapshot(
                    of: snapshottingView,
                    as: .image,
                    named: named,
                    testName: testName,
                )
            }
        }
    }

    private func fixedTestDate() -> Date {
        Date(timeIntervalSince1970: 40000)
    }

    /// The first 24 word BIP39 test vector (all zero entropy).
    private var bip39Valid24Words: [String] {
        Array(repeating: "abandon", count: 23) + ["art"]
    }

    /// Words 3 and 8 aren't in the BIP39 wordlist.
    private var phraseWithUnknownWords: RecoveryPhrase {
        var words = Array(repeating: "abandon", count: 11) + ["about"]
        words[2] = "abandom"
        words[7] = "zooo"
        return RecoveryPhrase(title: "Savings", words: words, standard: .bip39, passphrase: "")
    }

    /// A valid 33 word SLIP-39 share from the python-shamir-mnemonic test vectors.
    private var slip39ShareWords: [String] {
        "theory painting academic academic armed sweater year military elder discuss acne wildlife boring employer fused large satoshi bundle carbon diagnose anatomy hamster leaves tracks paces beyond phantom capital marvel lips brave detect luck"
            .split(separator: " ")
            .map(String.init)
    }
}
