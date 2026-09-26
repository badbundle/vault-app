import Combine
import Foundation
import SwiftUI
import TestHelpers
import Testing
import VaultKeygen
@testable import VaultFeed
@testable import VaultiOS

@MainActor
final class EncryptedItemDetailViewSnapshotTests {
    @Test
    func initialState() throws {
        let viewModel = try makeViewModel()

        snapshotScenarios(view: makeSUT(viewModel: viewModel))
    }

    @Test
    func incorrectPassword() async throws {
        let viewModel = try makeViewModel()
        viewModel.enteredEncryptionPassword = "incorrect password"

        // Fully await the failed decryption (fast testing deriver) so the error
        // state renders deterministically.
        await viewModel.startDecryption()
        #expect(viewModel.state.presentationError?.userTitle == "Incorrect Password")

        snapshotScenarios(
            view: makeSUT(viewModel: viewModel),
            dynamicTypeSizes: [.xSmall, .medium, .xxLarge, .accessibility2],
        )
    }
}

// MARK: - Helpers

extension EncryptedItemDetailViewSnapshotTests {
    /// Outside a `NavigationStack`: its bar's Cancel button would vanish in the dark
    /// references (see `assertSnapshot(of:colorScheme:)`).
    private func makeSUT(viewModel: EncryptedItemDetailViewModel) -> some View {
        EncryptedItemDetailView(viewModel: viewModel, openDetailSubject: PassthroughSubject())
    }

    /// A secure note encrypted with the password "hello", using the fast testing key deriver.
    private func makeViewModel() throws -> EncryptedItemDetailViewModel {
        let note = SecureNote(title: "Hello", contents: "World", format: .plain)
        let key = try VaultKeyDeriver.testing.createEncryptionKey(password: "hello")
        let item = try VaultItemEncryptor(key: key).encrypt(item: note)
        let keyDeriverFactory = VaultKeyDeriverFactoryMock()
        keyDeriverFactory.lookupVaultKeyDeriverHandler = { _ in .testing }
        return EncryptedItemDetailViewModel(
            item: item,
            metadata: anyVaultItemMetadata(),
            keyDeriverFactory: keyDeriverFactory,
        )
    }

    private func snapshotScenarios(
        view: some View,
        dynamicTypeSizes: [DynamicTypeSize] = [.xSmall, .medium, .xxLarge],
        testName: String = #function,
    ) {
        for colorScheme in [ColorScheme.light, .dark] {
            for dynamicTypeSize in dynamicTypeSizes {
                let snapshottingView = view
                    .dynamicTypeSize(dynamicTypeSize)
                    .framedForTest()

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
