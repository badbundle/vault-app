import Foundation
import SwiftUI
import TestHelpers
import Testing
@testable import VaultFeed
@testable import VaultiOS

@MainActor
struct SettingsDangerViewSnapshotTests {
    @Test
    func overview() {
        for colorScheme in [ColorScheme.light, .dark] {
            for dynamicTypeSize in [DynamicTypeSize.xSmall, .medium, .xxLarge] {
                let sut = makeSUT(viewModel: makeViewModel(), dynamicTypeSize: dynamicTypeSize, height: 760)

                assertSnapshot(of: sut, colorScheme: colorScheme, named: "\(colorScheme)_\(dynamicTypeSize)")
            }
        }
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func confirming(colorScheme: ColorScheme) {
        let viewModel = makeViewModel()
        viewModel.askToConfirm()

        assertSnapshot(of: makeSUT(viewModel: viewModel), colorScheme: colorScheme, named: "\(colorScheme)")
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func deleting(colorScheme: ColorScheme) async {
        let deleter = VaultStoreDeleterMock()
        // Holds the deletion in flight until the test is done with it.
        deleter.deleteVaultHandler = { try await Task.sleep(for: .seconds(60)) }
        let viewModel = makeViewModel(deleter: deleter)
        viewModel.askToConfirm()
        let deletion = Task { await viewModel.deleteEntireVault() }
        defer { deletion.cancel() }
        while !viewModel.isDeleting {
            await Task.yield()
        }

        assertSnapshot(of: makeSUT(viewModel: viewModel), colorScheme: colorScheme, named: "\(colorScheme)")
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func failed(colorScheme: ColorScheme) async {
        let viewModel = makeViewModel(policy: DeviceAuthenticationPolicyAlwaysDeny())
        viewModel.askToConfirm()
        await viewModel.deleteEntireVault()

        assertSnapshot(of: makeSUT(viewModel: viewModel), colorScheme: colorScheme, named: "\(colorScheme)")
    }
}

// MARK: - Helpers

extension SettingsDangerViewSnapshotTests {
    private func makeViewModel(
        deleter: VaultStoreDeleterMock = VaultStoreDeleterMock(),
        policy: some DeviceAuthenticationPolicy = DeviceAuthenticationPolicyAlwaysAllow(),
    ) -> SettingsDangerViewModel {
        SettingsDangerViewModel(
            dataModel: anyVaultDataModel(vaultDeleter: deleter),
            authenticationService: DeviceAuthenticationService(policy: policy),
        )
    }

    private func makeSUT(
        viewModel: SettingsDangerViewModel,
        dynamicTypeSize: DynamicTypeSize = .medium,
        height: CGFloat = 400,
    ) -> some View {
        // The sheet sizes itself to its content, but that content is in a scroll view, which has no height of its
        // own. A height a little taller than the content stands in for the sheet.
        SettingsDangerView(viewModel: viewModel)
            .dynamicTypeSize(dynamicTypeSize)
            .frame(width: 390, height: height, alignment: .top)
            .background(Color(UIColor.systemBackground))
    }
}
