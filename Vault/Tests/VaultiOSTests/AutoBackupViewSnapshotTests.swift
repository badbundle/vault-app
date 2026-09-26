import Foundation
import SwiftUI
import TestHelpers
import Testing
@testable import VaultFeed
@testable import VaultiOS

@MainActor
struct AutoBackupViewSnapshotTests {
    @Test
    func locked() {
        let sut = makeSUT(
            dataModel: anyVaultDataModel(),
            viewModel: makeViewModel(),
        )

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func passwordNotCreated() async {
        let sut = makeSUT(
            dataModel: await passwordNotCreatedDataModel(),
            viewModel: makeViewModel(),
        )

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func disabled() async {
        let sut = makeSUT(
            dataModel: await passwordFetchedDataModel(),
            viewModel: makeViewModel(),
        )

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func enabledUnconfigured() async {
        let sut = makeSUT(
            dataModel: await passwordFetchedDataModel(),
            viewModel: makeViewModel(
                status: .idle,
                configuration: enabledConfiguration(),
                providerStates: [unconfiguredProviderState()],
            ),
        )

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func enabledConfigured() async {
        let sut = makeSUT(
            dataModel: await passwordFetchedDataModel(),
            viewModel: makeViewModel(
                status: .completed(Date(timeIntervalSince1970: 1_700_000_000)),
                configuration: enabledConfiguration(providerID: "icloud-drive"),
                providerStates: [configuredProviderState()],
            ),
        )

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func backingUp() async {
        let sut = makeSUT(
            dataModel: await passwordFetchedDataModel(),
            viewModel: makeViewModel(
                status: .backingUp(anyRun(trigger: .automatic, progress: .init(phase: .rendering, phaseFraction: 0.4))),
                configuration: enabledConfiguration(providerID: "icloud-drive"),
                providerStates: [configuredProviderState()],
            ),
        )

        assertSnapshot(of: sut, as: .image)
    }

    /// The running state carries the most detail, so check it holds up in dark mode at a large text size.
    @Test
    func backingUp_manualDarkLargeText() async {
        let sut = makeSUT(
            dataModel: await passwordFetchedDataModel(),
            viewModel: makeViewModel(
                status: .backingUp(anyRun(trigger: .manual, progress: .init(phase: .saving))),
                configuration: enabledConfiguration(providerID: "icloud-drive"),
                providerStates: [configuredProviderState()],
            ),
            dynamicTypeSize: .xxLarge,
        )
        .environment(\.colorScheme, .dark)

        // The environment alone doesn't reach UIKit-backed rows; the host's traits do.
        assertSnapshot(of: sut, as: .image(traits: UITraitCollection(userInterfaceStyle: .dark)))
    }

    @Test
    func cleaningUp() async {
        let sut = makeSUT(
            dataModel: await passwordFetchedDataModel(),
            viewModel: makeViewModel(
                status: .cleaningUp,
                configuration: enabledConfiguration(providerID: "icloud-drive"),
                providerStates: [configuredProviderState()],
            ),
        )

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func backupComplete() async {
        let viewModel = makeViewModel(
            status: .completed(Date(timeIntervalSince1970: 1_700_000_000)),
            configuration: enabledConfiguration(providerID: "icloud-drive"),
            providerStates: [configuredProviderState()],
        )
        viewModel.showsBackupCompleteNotice = true
        let sut = makeSUT(
            dataModel: await passwordFetchedDataModel(),
            viewModel: viewModel,
        )

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func statusError() async {
        let sut = makeSUT(
            dataModel: await passwordFetchedDataModel(),
            viewModel: makeViewModel(
                status: .error(.writeFailed(reason: "The folder could not be reached")),
                configuration: enabledConfiguration(providerID: "icloud-drive"),
                providerStates: [configuredProviderState()],
            ),
        )

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func configureError() async {
        let viewModel = makeViewModel(
            status: .idle,
            configuration: enabledConfiguration(),
            providerStates: [unconfiguredProviderState()],
        )
        viewModel.configureError = .accessDenied
        let sut = makeSUT(
            dataModel: await passwordFetchedDataModel(),
            viewModel: viewModel,
        )

        assertSnapshot(of: sut, as: .image)
    }
}

// MARK: - Helpers

extension AutoBackupViewSnapshotTests {
    private func makeSUT(
        dataModel: VaultDataModel,
        viewModel: AutoBackupViewModel,
        dynamicTypeSize: DynamicTypeSize = .large,
    ) -> some View {
        NavigationStack {
            AutoBackupView(viewModel: viewModel)
        }
        .dynamicTypeSize(dynamicTypeSize)
        .environment(dataModel)
        .environment(DeviceAuthenticationService(policy: .alwaysAllow))
        .environment(anyVaultInjector())
        .framedForTest()
    }

    private func makeViewModel(
        status: AutoBackupStatus = .disabled,
        configuration: AutoBackupConfiguration = .init(),
        providerStates: [AutoBackupViewModel.ProviderDisplayState] = [],
    ) -> AutoBackupViewModel {
        AutoBackupViewModel(
            service: AutoBackupServiceMock(status: status, configuration: configuration),
            initialProviderStates: providerStates,
        )
    }

    private func anyRun(trigger: AutoBackupRun.Trigger, progress: AutoBackupProgress) -> AutoBackupRun {
        AutoBackupRun(trigger: trigger, startedAt: Date(timeIntervalSince1970: 1_700_000_000), progress: progress)
    }

    private func passwordNotCreatedDataModel() async -> VaultDataModel {
        let backupPasswordStore = BackupPasswordStoreMock()
        backupPasswordStore.fetchPasswordHandler = { nil }
        let dataModel = anyVaultDataModel(backupPasswordStore: backupPasswordStore)
        await dataModel.loadBackupPassword()
        return dataModel
    }

    private func passwordFetchedDataModel() async -> VaultDataModel {
        let backupPasswordStore = BackupPasswordStoreMock()
        backupPasswordStore.fetchPasswordHandler = { .init(
            key: .random(),
            salt: .random(count: 32),
            keyDervier: .testing,
        ) }
        let dataModel = anyVaultDataModel(backupPasswordStore: backupPasswordStore)
        await dataModel.loadBackupPassword()
        return dataModel
    }

    private func enabledConfiguration(providerID: String? = nil) -> AutoBackupConfiguration {
        AutoBackupConfiguration(
            isEnabled: true,
            retentionDays: .days30,
            providerID: providerID,
            providerConfigs: [:],
            lastBackupHash: nil,
            lastBackupDate: nil,
        )
    }

    private func unconfiguredProviderState() -> AutoBackupViewModel.ProviderDisplayState {
        .init(
            id: "icloud-drive",
            displayName: "iCloud Drive",
            iconSystemName: "icloud",
            isConfigured: false,
            folderSummary: nil,
        )
    }

    private func configuredProviderState() -> AutoBackupViewModel.ProviderDisplayState {
        .init(
            id: "icloud-drive",
            displayName: "iCloud Drive",
            iconSystemName: "icloud",
            isConfigured: true,
            folderSummary: "Vault Backups",
        )
    }
}
