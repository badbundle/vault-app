import Combine
import CryptoEngine
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
    func layout() async {
        await snapshotScenarios {
            BackupKeyDecryptorView(viewModel: makeViewModel())
        }
    }

    /// Recreating the key says how long it can take, with Cancel still enabled as the way out.
    @Test
    func layoutDecrypting() async {
        await forEachScenario { snapshot in
            let deriver = BlockingKeyDeriver()
            let viewModel = makeViewModel(deriver: deriver)
            viewModel.enteredPassword = "password"
            let decryption = Task { await viewModel.attemptDecryption() }
            while !viewModel.isDecrypting {
                await Task.yield()
            }

            snapshot(BackupKeyDecryptorView(viewModel: viewModel))

            decryption.cancel()
            deriver.release()
            await decryption.value
        }
    }

    @Test
    func layoutWrongPassword() async {
        await snapshotScenarios {
            let decoder = EncryptedVaultDecoderMock()
            decoder.decryptAndDecodeHandler = { _, _ in throw EncryptedVaultDecoderError.decryption }
            let viewModel = makeViewModel(decoder: decoder)
            viewModel.enteredPassword = "wrong password"

            // Fully await the failed decryption (fast testing deriver) so the
            // error state renders deterministically.
            await viewModel.attemptDecryption()
            #expect(viewModel.decryptionKeyState.isError)

            return BackupKeyDecryptorView(viewModel: viewModel)
        }
    }
}

// MARK: - Helpers

extension BackupKeyDecryptorViewSnapshotTests {
    private func makeViewModel(
        decoder: EncryptedVaultDecoderMock = EncryptedVaultDecoderMock(),
    ) -> BackupKeyDecryptorViewModel {
        let deriverFactory = VaultKeyDeriverFactoryMock()
        deriverFactory.lookupVaultKeyDeriverHandler = { _ in .testing }
        return makeViewModel(deriverFactory: deriverFactory, decoder: decoder)
    }

    private func makeViewModel(deriver: BlockingKeyDeriver) -> BackupKeyDecryptorViewModel {
        let deriverFactory = VaultKeyDeriverFactoryMock()
        deriverFactory.lookupVaultKeyDeriverHandler = { _ in
            VaultKeyDeriver(deriver: deriver, signature: .testing)
        }
        return makeViewModel(deriverFactory: deriverFactory, decoder: EncryptedVaultDecoderMock())
    }

    private func makeViewModel(
        deriverFactory: VaultKeyDeriverFactoryMock,
        decoder: EncryptedVaultDecoderMock,
    ) -> BackupKeyDecryptorViewModel {
        BackupKeyDecryptorViewModel(
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

    /// Blocks key derivation until `release()`, so tests can pin the view while the key is being recreated.
    // swiftlint:disable:next no_unchecked_sendable
    private final class BlockingKeyDeriver: KeyDeriver, @unchecked Sendable {
        private let semaphore = DispatchSemaphore(value: 0)

        var uniqueAlgorithmIdentifier: String {
            "blocking"
        }

        func key(password _: Data, salt _: Data) throws -> KeyData<32> {
            semaphore.wait()
            return .zero()
        }

        func release() {
            semaphore.signal()
        }
    }

    /// Snapshots a fresh view in each appearance, at the smallest, default and a large text size.
    private func snapshotScenarios(
        testName: String = #function,
        makeView: () async -> some View,
    ) async {
        await forEachScenario(testName: testName) { snapshot in
            await snapshot(makeView())
        }
    }

    /// Runs `scenario` in each appearance and text size, for it to set up its view, snapshot it with the closure it's
    /// given, and tidy up after.
    private func forEachScenario(
        testName: String = #function,
        scenario: @MainActor (_ snapshot: (any View) -> Void) async -> Void,
    ) async {
        for colorScheme in [ColorScheme.light, .dark] {
            for dynamicTypeSize in [DynamicTypeSize.xSmall, .medium, .xxLarge] {
                await scenario { view in
                    // In a navigation stack, for the title and Cancel.
                    let snapshottingView = NavigationStack {
                        AnyView(view)
                    }
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
}
