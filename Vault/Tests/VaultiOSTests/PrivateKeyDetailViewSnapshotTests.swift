import Foundation
import SwiftUI
import TestHelpers
import Testing
import VaultFeed
@testable import VaultiOS

/// A private key is protected as a recovery phrase is (G102, G103): locked until device authentication passes, masked
/// until
/// tapped, and hidden while Vault isn't in the foreground or the screen is captured.
@MainActor
final class PrivateKeyDetailViewSnapshotTests {
    @Test
    func lockedState() {
        snapshotScenarios(view: makeSUT(viewModel: makeEditingViewModel()), dynamicTypeSizes: [.medium])
    }

    /// Without a passcode, there's no way past the lock.
    @Test
    func lockedStateNoAuthentication() {
        snapshotScenarios(
            view: makeSUT(viewModel: makeEditingViewModel()),
            deviceAuthenticationPolicy: .cannotAuthenticate,
            dynamicTypeSizes: [.medium],
        )
    }

    @Test
    func wif_masked() {
        let viewModel = makeEditingViewModel(privateKey: .init(
            title: "Paper wallet",
            key: wifKey,
            contents: "The one printed in 2017. Long-term savings, don't touch.",
        ))
        viewModel.isLocked = false

        snapshotScenarios(view: makeSUT(viewModel: viewModel))
    }

    @Test
    func wif_revealed() {
        let viewModel = makeEditingViewModel(privateKey: .init(title: "Paper wallet", key: wifKey))
        viewModel.isLocked = false

        snapshotScenarios(view: makeSUT(viewModel: viewModel), beforeEach: { viewModel.isKeyRevealed = true })
    }

    @Test
    func invalidChecksum_revealed() {
        let viewModel = makeEditingViewModel(privateKey: .init(
            title: "Paper wallet",
            key: String(wifKey.dropLast()) + "8",
        ))
        viewModel.isLocked = false

        snapshotScenarios(
            view: makeSUT(viewModel: viewModel),
            dynamicTypeSizes: [.medium],
            beforeEach: { viewModel.isKeyRevealed = true },
        )
    }

    /// A key of many lines, as an armored key is, shown as it was entered.
    @Test
    func armoredKey_revealed() {
        let viewModel = makeEditingViewModel(privateKey: .init(title: "Server", key: madeUpArmoredKey))
        viewModel.isLocked = false

        snapshotScenarios(
            view: makeSUT(viewModel: viewModel),
            dynamicTypeSizes: [.medium],
            beforeEach: { viewModel.isKeyRevealed = true },
        )
    }

    @Test
    func otherText_masked() {
        let viewModel = makeEditingViewModel(privateKey: .init(title: "Something else", key: "anything at all"))
        viewModel.isLocked = false

        snapshotScenarios(view: makeSUT(viewModel: viewModel), dynamicTypeSizes: [.medium])
    }

    @Test
    func hiddenWhileInactive() {
        let viewModel = makeEditingViewModel()
        viewModel.isLocked = false

        snapshotScenarios(
            view: makeSUT(viewModel: viewModel),
            scenePhase: .inactive,
            dynamicTypeSizes: [.medium],
            beforeEach: { viewModel.isKeyRevealed = true },
        )
    }

    @Test
    func hiddenWhileCaptured() {
        let viewModel = makeEditingViewModel()
        viewModel.isLocked = false

        let sut = makeSUT(viewModel: viewModel)
            .environment(\.isSceneCaptured, true)

        snapshotScenarios(view: sut, dynamicTypeSizes: [.medium], beforeEach: { viewModel.isKeyRevealed = true })
    }

    @Test
    func editMode_newKey() {
        let viewModel = makeCreatingViewModel()

        snapshotScenarios(view: makeSUT(viewModel: viewModel), height: 1600)
    }

    @Test
    func editMode_newKeyPasted() {
        let viewModel = makeCreatingViewModel()
        viewModel.editingModel.detail.key = wifKey

        snapshotScenarios(view: makeSUT(viewModel: viewModel), dynamicTypeSizes: [.medium], height: 1600)
    }

    /// Edit isn't a way around the mask.
    @Test
    func editMode_existingKeyMasked() {
        let viewModel = makeEditingViewModel()
        viewModel.isLocked = false
        viewModel.startEditing()
        viewModel.showEditorStep(.content)

        snapshotScenarios(view: makeSUT(viewModel: viewModel), dynamicTypeSizes: [.medium], height: 1600)
    }

    @Test
    func editMode_securityStepNeedsPassword() {
        let viewModel = makeCreatingViewModel()
        viewModel.editingModel.detail.key = wifKey
        viewModel.continueInEditor()
        viewModel.continueInEditor()
        viewModel.continueInEditor()

        snapshotScenarios(view: makeSUT(viewModel: viewModel), dynamicTypeSizes: [.medium], height: 1800)
    }
}

// MARK: - Helpers

extension PrivateKeyDetailViewSnapshotTests {
    private func makeSUT(viewModel: PrivateKeyDetailViewModel) -> some View {
        PrivateKeyDetailView(viewModel: viewModel, navigationPath: .constant(NavigationPath()))
    }

    private func makeEditingViewModel(
        privateKey: PrivateKey = .init(title: "Wallet", key: "KwdMAjGmerYanjeui5SHS7JkmpZvVipYvB2LJGU1ZxJwYvP98617"),
    ) -> PrivateKeyDetailViewModel {
        PrivateKeyDetailViewModel(
            mode: .editing(
                key: privateKey,
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
            editor: PrivateKeyDetailEditorMock(),
        )
    }

    private func makeCreatingViewModel() -> PrivateKeyDetailViewModel {
        let viewModel = PrivateKeyDetailViewModel(
            mode: .creating,
            dataModel: anyVaultDataModel(),
            editor: PrivateKeyDetailEditorMock(),
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
                // The view masks the key again when it disappears, which it does after each snapshot.
                beforeEach()
                let snapshottingView = view
                    .environment(\.scenePhase, scenePhase)
                    .dynamicTypeSize(dynamicTypeSize)
                    .framedForTest(height: height)
                    .environment(DeviceAuthenticationService(policy: deviceAuthenticationPolicy))
                let named = "\(colorScheme)_\(dynamicTypeSize)"

                assertSnapshot(
                    of: snapshottingView,
                    colorScheme: colorScheme,
                    named: named,
                    testName: testName,
                )
            }
        }
    }

    private func fixedTestDate() -> Date {
        Date(timeIntervalSince1970: 40000)
    }

    /// The Bitcoin wiki's WIF example, a public test key.
    private var wifKey: String {
        "KwdMAjGmerYanjeui5SHS7JkmpZvVipYvB2LJGU1ZxJwYvP98617"
    }

    /// An armored block's shape, with a made-up body that isn't a key.
    private var madeUpArmoredKey: String {
        [
            "-----BEGIN EXAMPLE KEY-----",
            "VGhpcyBpcyBub3QgYSBrZXksIG9ubHkgdGV4dCBpbiB0aGUgc2hhcGUgb2YgYW4g",
            "YXJtb3JlZCBibG9jaywgZm9yIFZhdWx0J3Mgc25hcHNob3QgdGVzdHMu",
            "-----END EXAMPLE KEY-----",
        ].joined(separator: "\n")
    }
}
