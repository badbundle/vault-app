import Foundation
import SwiftUI
import TestHelpers
import Testing
import VaultFeed
@testable import VaultiOS

/// The new-item sheet once a kind of item has been chosen.
@MainActor
struct CreateItemFlowViewSnapshotTests {
    /// The item's first step, which now has a progress bar, and Back to return to choosing the kind of item.
    @Test
    func chosenNote_firstStepHasBackToTheChoice() {
        let sut = makeSUT(creatingItem: .secureNote, policy: DeviceAuthenticationPolicyAlwaysAllow())

        snapshotScenarios(view: sut, height: 900)
    }

    /// Without a passcode there's no recovery phrase to make, so the sheet says why in place of its first step.
    @Test
    func chosenRecoveryPhrase_withoutPasscode() {
        let sut = makeSUT(creatingItem: .recoveryPhrase, policy: DeviceAuthenticationPolicyCannotAuthenticate())

        snapshotScenarios(view: sut, height: 500)
    }

    // MARK: - Helpers

    private func makeSUT(creatingItem: CreatingItem, policy: some DeviceAuthenticationPolicy) -> some View {
        CreateItemFlowView(
            previewGenerator: VaultItemPreviewViewGeneratorMock.defaultMock(),
            copyActionHandler: VaultItemCopyActionHandlerMock(),
            navigationPath: .constant(NavigationPath()),
            flow: CreateItemFlow(creatingItem: creatingItem),
        )
        .environment(anyVaultDataModel())
        .environment(anyVaultInjector())
        .environment(DeviceAuthenticationService(policy: policy))
    }

    private func snapshotScenarios(view: some View, height: CGFloat, testName: String = #function) {
        for colorScheme in [ColorScheme.light, .dark] {
            let snapshottingView = view
                // The sheet the flow is shown in.
                .background(Color(UIColor.systemBackground))
                .framedForTest(height: height)

            assertSnapshot(of: snapshottingView, colorScheme: colorScheme, named: "\(colorScheme)", testName: testName)
        }
    }
}
