import Combine
import Foundation
import FoundationExtensions
import SwiftUI
import TestHelpers
import Testing
import VaultBackup
import VaultKeygen
@testable import VaultFeed
@testable import VaultiOS

@MainActor
final class BackupKeyDecryptorViewSnapshotTests {
    @Test
    func layout() {
        for colorScheme in [ColorScheme.light, .dark] {
            for dynamicTypeSize in [DynamicTypeSize.xSmall, .medium, .xxLarge] {
                let snapshottingView = NavigationStack {
                    BackupKeyDecryptorView(viewModel: makeViewModel())
                }
                .dynamicTypeSize(dynamicTypeSize)
                .preferredColorScheme(colorScheme)
                .framedForTest()

                assertSnapshot(
                    of: snapshottingView,
                    as: .image,
                    named: "\(colorScheme)_\(dynamicTypeSize)",
                )
            }
        }
    }

    @Test
    func layoutDecryptFailure() async {
        let decoder = EncryptedVaultDecoderMock()
        decoder.decryptAndDecodeHandler = { _, _ in throw TestError() }
        let viewModel = makeViewModel(decoder: decoder)
        viewModel.enteredPassword = "wrong password"

        // Fully await the failed decryption (fast testing deriver) so the
        // error state renders deterministically.
        await viewModel.attemptDecryption()
        #expect(viewModel.decryptionKeyState.isError)

        let snapshottingView = NavigationStack {
            BackupKeyDecryptorView(viewModel: viewModel)
        }
        .dynamicTypeSize(.medium)
        .preferredColorScheme(.light)
        .framedForTest()

        assertSnapshot(of: snapshottingView, as: .image)
    }
}

// MARK: - Helpers

extension BackupKeyDecryptorViewSnapshotTests {
    private func makeViewModel(
        decoder: EncryptedVaultDecoderMock = EncryptedVaultDecoderMock(),
    ) -> BackupKeyDecryptorViewModel {
        let deriverFactory = VaultKeyDeriverFactoryMock()
        deriverFactory.lookupVaultKeyDeriverHandler = { _ in .testing }
        return BackupKeyDecryptorViewModel(
            encryptedVault: anyEncryptedVault(),
            keyDeriverFactory: deriverFactory,
            encryptedVaultDecoder: decoder,
            decryptedVaultSubject: PassthroughSubject(),
        )
    }

    private func anyEncryptedVault() -> EncryptedVault {
        EncryptedVault(
            version: "1.0.0",
            data: Data(repeating: 0xAB, count: 50),
            authentication: Data(),
            encryptionIV: Data(),
            keygenSalt: Data(repeating: 0xCD, count: 32),
            keygenSignature: VaultKeyDeriver.Signature.testing.rawValue,
        )
    }
}
