import CryptoEngine
import Foundation
import FoundationExtensions
import SwiftUI
import TestHelpers
import Testing
import VaultKeygen
import VaultSettings
@testable import VaultFeed
@testable import VaultiOS

@MainActor
final class BackupKeyChangeViewSnapshotTests {
    @Test
    func layout() {
        snapshotScenarios {
            BackupKeyChangeView(viewModel: makeViewModel())
        }
    }

    @Test
    func layoutAuthenticated() {
        snapshotScenarios {
            let viewModel = makeViewModel()
            viewModel.permissionState = .allowed
            return BackupKeyChangeView(viewModel: viewModel)
        }
    }

    /// The Cancel button must render enabled while the keygen runs — it
    /// is the only escape hatch from the up-to-3-minute derivation, since
    /// interactive dismissal is disabled during `.creating`.
    @Test
    func layoutCreatingState() async {
        for colorScheme in [ColorScheme.light, .dark] {
            let deriver = BlockingKeyDeriver()
            let viewModel = makeViewModel(deriver: deriver)
            viewModel.permissionState = .allowed
            viewModel.newlyEnteredPassword = "password"
            viewModel.newlyEnteredPasswordConfirm = "password"

            let keygen = Task { await viewModel.saveEnteredPassword() }
            while viewModel.newPassword != .creating {
                await Task.yield()
            }

            // Wrapped in a NavigationStack so the toolbar renders: the
            // point of this snapshot is the enabled Cancel button.
            let snapshottingView = NavigationStack { BackupKeyChangeView(viewModel: viewModel) }
                .dynamicTypeSize(.medium)
                .preferredColorScheme(colorScheme)
                .framedForTest()
                .environment(makePasteboard())
                .environment(DeviceAuthenticationService(policy: DeviceAuthenticationPolicyAlwaysAllow()))
            assertSnapshot(
                of: snapshottingView,
                as: .image,
                named: "\(colorScheme)_medium",
            )

            keygen.cancel()
            deriver.release()
            await keygen.value
        }
    }
}

// MARK: - Helpers

extension BackupKeyChangeViewSnapshotTests {
    private func makeViewModel() -> BackupKeyChangeViewModel {
        BackupKeyChangeViewModel(
            dataModel: anyVaultDataModel(),
            authenticationService: DeviceAuthenticationService(policy: DeviceAuthenticationPolicyAlwaysAllow()),
            deriverFactory: VaultKeyDeriverFactoryImpl(),
        )
    }

    private func makeViewModel(deriver: BlockingKeyDeriver) -> BackupKeyChangeViewModel {
        let deriverFactory = VaultKeyDeriverFactoryMock()
        deriverFactory.makeVaultBackupKeyDeriverHandler = {
            VaultKeyDeriver(deriver: deriver, signature: .testing)
        }
        return BackupKeyChangeViewModel(
            dataModel: anyVaultDataModel(),
            authenticationService: DeviceAuthenticationService(policy: DeviceAuthenticationPolicyAlwaysAllow()),
            deriverFactory: deriverFactory,
        )
    }

    /// Blocks key derivation until `release()` so tests can pin the
    /// view in the `.creating` state.
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

    /// Builds a fresh view for every scenario.
    ///
    /// The view resets `permissionState` to `.undetermined` in `onDisappear`, so sharing one view —
    /// and therefore one view model — across the loop let the first snapshot tear down the state that
    /// the remaining five depended on. Every scenario now gets its own instance.
    private func snapshotScenarios(
        deviceAuthenticationPolicy: some DeviceAuthenticationPolicy = DeviceAuthenticationPolicyAlwaysAllow(),
        testName: String = #function,
        makeView: () -> some View,
    ) {
        let colorSchemes: [ColorScheme] = [.light, .dark]
        let dynamicTypeSizes: [DynamicTypeSize] = [.xSmall, .medium, .xxLarge]
        for colorScheme in colorSchemes {
            for dynamicTypeSize in dynamicTypeSizes {
                let snapshottingView = makeView()
                    .dynamicTypeSize(dynamicTypeSize)
                    .preferredColorScheme(colorScheme)
                    .framedForTest()
                    .environment(makePasteboard())
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

    private func makePasteboard() -> Pasteboard {
        Pasteboard(SystemPasteboardMock(), localSettings: LocalSettings(defaults: .init(userDefaults: .standard)))
    }
}
