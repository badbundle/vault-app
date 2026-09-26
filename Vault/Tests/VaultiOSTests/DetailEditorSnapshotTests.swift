import Foundation
import SwiftUI
import TestHelpers
import Testing
import VaultFeed
import VaultSettings
@testable import VaultiOS

/// The item editor's steps, as they're walked through when creating an item and opened from an existing item's
/// overview.
@MainActor
struct DetailEditorSnapshotTests {
    // MARK: - Code

    @Test
    func code_keyStep() {
        let viewModel = makeCodeCreating()
        viewModel.editingModel.detail.secretBase32String = "ABC!"

        snapshotScenarios(view: makeCodeView(viewModel: viewModel), height: 1400)
    }

    @Test
    func code_nameStep() {
        let viewModel = makeCodeCreating()
        viewModel.applyScannedCode(makeCode(issuer: "GitHub", accountName: "bradley@example.com"))

        snapshotScenarios(view: makeCodeView(viewModel: viewModel))
    }

    @Test
    func code_appearanceStep() async {
        let dataModel = await makeDataModelWithTags()
        let viewModel = makeCodeCreating(dataModel: dataModel)
        viewModel.applyScannedCode(makeCode(issuer: "GitHub", accountName: "bradley@example.com"))
        viewModel.continueInEditor()
        viewModel.editingModel.detail.color = ItemColorPicker.palette[9].color
        viewModel.editingModel.detail.tags = Set(dataModel.allTags.prefix(2).map(\.id))

        snapshotScenarios(view: makeCodeView(viewModel: viewModel))
    }

    @Test
    func code_securityStep() {
        let viewModel = makeCodeCreating()
        viewModel.applyScannedCode(makeCode(issuer: "GitHub"))
        viewModel.continueInEditor()
        viewModel.continueInEditor()

        snapshotScenarios(view: makeCodeView(viewModel: viewModel), height: 1200)
    }

    @Test
    func code_securityStepHiddenWithKillphrase() {
        let viewModel = makeCodeCreating()
        viewModel.applyScannedCode(makeCode(issuer: "GitHub"))
        viewModel.continueInEditor()
        viewModel.continueInEditor()
        viewModel.editingModel.detail.viewConfig = .requiresSearchPassphrase
        viewModel.editingModel.detail.lockState = .lockedWithNativeSecurity
        viewModel.editingModel.detail.killphraseEnabled = true
        viewModel.editingModel.detail.newKillphrase = "  "

        snapshotScenarios(view: makeCodeView(viewModel: viewModel), dynamicTypeSizes: [.medium], height: 1600)
    }

    @Test
    func code_stepOpenedFromOverview() {
        let viewModel = makeCodeEditing()
        viewModel.startEditing()
        viewModel.showEditorStep(.details)

        snapshotScenarios(view: makeCodeView(viewModel: viewModel), dynamicTypeSizes: [.medium])
    }

    // MARK: - Note

    @Test
    func note_contentStep() {
        let viewModel = makeNoteCreating()
        viewModel.editingModel.detail.contents = "Home Wi-Fi\nNetwork: Guest\nPassword: correct horse"

        snapshotScenarios(view: makeNoteView(viewModel: viewModel), height: 1200)
    }

    @Test
    func note_securityStep() {
        let viewModel = makeNoteCreating()
        viewModel.continueInEditor()
        viewModel.continueInEditor()

        snapshotScenarios(view: makeNoteView(viewModel: viewModel), height: 1500)
    }

    @Test
    func note_overview() {
        let viewModel = SecureNoteDetailViewModel(
            mode: .editing(
                note: .init(title: "Home Wi-Fi", contents: "Home Wi-Fi\nNetwork: Guest", format: .markdown),
                metadata: anyVaultItemMetadata(lockState: .lockedWithNativeSecurity),
                existingKey: nil,
            ),
            dataModel: anyVaultDataModel(),
            editor: SecureNoteDetailEditorMock(),
        )
        viewModel.isLocked = false
        viewModel.startEditing()

        snapshotScenarios(view: makeNoteView(viewModel: viewModel))
    }

    // MARK: - Recovery phrase

    @Test
    func recoveryPhrase_nameStep() {
        let viewModel = makePhraseCreating()
        viewModel.editingModel.detail.setWordCount(12)
        for (index, word) in (Array(repeating: "abandon", count: 11) + ["about"]).enumerated() {
            viewModel.editingModel.detail.applyInput(word, at: index)
        }
        viewModel.continueInEditor()
        viewModel.editingModel.detail.title = "Savings"

        snapshotScenarios(view: makePhraseView(viewModel: viewModel))
    }

    @Test
    func recoveryPhrase_securityStepNeedsPassword() {
        let viewModel = makePhraseCreating()
        viewModel.editingModel.detail.setWordCount(12)
        for (index, word) in (Array(repeating: "abandon", count: 11) + ["about"]).enumerated() {
            viewModel.editingModel.detail.applyInput(word, at: index)
        }
        viewModel.continueInEditor()
        viewModel.continueInEditor()
        viewModel.continueInEditor()

        snapshotScenarios(view: makePhraseView(viewModel: viewModel), height: 1500)
    }
}

// MARK: - Helpers

extension DetailEditorSnapshotTests {
    private func makeCodeView(viewModel: OTPCodeDetailViewModel) -> some View {
        OTPCodeDetailView(
            viewModel: viewModel,
            navigationPath: .constant(NavigationPath()),
            previewGenerator: VaultItemPreviewViewGeneratorMock.defaultMock(),
            copyActionHandler: VaultItemCopyActionHandlerMock(),
            presentationMode: nil,
        )
        .environment(Pasteboard(
            SystemPasteboardMock(),
            localSettings: LocalSettings(defaults: .init(userDefaults: .standard)),
        ))
        .environment(anyVaultInjector())
    }

    private func makeNoteView(viewModel: SecureNoteDetailViewModel) -> some View {
        SecureNoteDetailView(viewModel: viewModel, navigationPath: .constant(NavigationPath()))
    }

    private func makePhraseView(viewModel: RecoveryPhraseDetailViewModel) -> some View {
        RecoveryPhraseDetailView(viewModel: viewModel, navigationPath: .constant(NavigationPath()))
    }

    private func makeCodeCreating(dataModel: VaultDataModel? = nil) -> OTPCodeDetailViewModel {
        let viewModel = OTPCodeDetailViewModel(
            mode: .creating(),
            dataModel: dataModel ?? anyVaultDataModel(),
            editor: OTPCodeDetailEditorMock(),
        )
        viewModel.startEditing()
        return viewModel
    }

    private func makeCodeEditing() -> OTPCodeDetailViewModel {
        OTPCodeDetailViewModel(
            mode: .editing(
                code: makeCode(issuer: "GitHub", accountName: "bradley@example.com"),
                metadata: anyVaultItemMetadata(),
            ),
            dataModel: anyVaultDataModel(),
            editor: OTPCodeDetailEditorMock(),
        )
    }

    private func makeNoteCreating() -> SecureNoteDetailViewModel {
        let viewModel = SecureNoteDetailViewModel(
            mode: .creating,
            dataModel: anyVaultDataModel(),
            editor: SecureNoteDetailEditorMock(),
        )
        viewModel.startEditing()
        return viewModel
    }

    private func makePhraseCreating() -> RecoveryPhraseDetailViewModel {
        let viewModel = RecoveryPhraseDetailViewModel(
            mode: .creating,
            dataModel: anyVaultDataModel(),
            editor: RecoveryPhraseDetailEditorMock(),
            locale: Locale(identifier: "en_US"),
        )
        viewModel.startEditing()
        return viewModel
    }

    private func makeCode(issuer: String, accountName: String = "") -> OTPAuthCode {
        OTPAuthCode(
            type: .totp(period: 30),
            data: .init(
                secret: .init(data: Data(repeating: 0xAF, count: 10), format: .base32),
                accountName: accountName,
                issuer: issuer,
            ),
        )
    }

    private func makeDataModelWithTags() async -> VaultDataModel {
        let tags = [
            anyVaultItemTag(name: "Work", color: .tagDefault, iconName: "briefcase.fill"),
            anyVaultItemTag(name: "Personal", color: .init(red: 0.2, green: 0.72, blue: 0.45), iconName: "person.fill"),
        ]
        let tagStore = VaultTagStoreStub()
        tagStore.retrieveTagsHandler = { tags }
        let dataModel = anyVaultDataModel(vaultTagStore: tagStore)
        await dataModel.reloadTags()
        return dataModel
    }

    private func snapshotScenarios(
        view: some View,
        dynamicTypeSizes: [DynamicTypeSize] = [.xSmall, .medium, .xxLarge],
        height: CGFloat = 1000,
        testName: String = #function,
    ) {
        for colorScheme in [ColorScheme.light, .dark] {
            for dynamicTypeSize in dynamicTypeSizes {
                let snapshottingView = view
                    // The sheet the editor is shown in.
                    .background(Color(uiColor: .systemBackground))
                    .dynamicTypeSize(dynamicTypeSize)
                    .framedForTest(height: height)
                    .environment(DeviceAuthenticationService(policy: DeviceAuthenticationPolicyAlwaysAllow()))
                    // A recovery phrase is hidden unless the app is in the foreground.
                    .environment(\.scenePhase, .active)

                assertSnapshot(
                    of: snapshottingView,
                    colorScheme: colorScheme,
                    named: "\(colorScheme)_\(dynamicTypeSize)",
                    testName: testName,
                )
            }
        }
    }
}
