import Combine
import Foundation
import Testing
@testable import VaultFeed

@MainActor
struct AutoBackupViewModelTests {
    @Test
    func init_seedsStatusAndConfigurationFromService() {
        var configuration = AutoBackupConfiguration()
        configuration.isEnabled = true
        let service = AutoBackupServiceMock(status: .idle, configuration: configuration)

        let sut = makeSUT(service: service)

        #expect(sut.status == .idle)
        #expect(sut.configuration == configuration)
    }

    @Test
    func init_hasNoSideEffects() {
        let service = AutoBackupServiceMock(status: .disabled, configuration: .init())

        _ = makeSUT(service: service)

        #expect(service.setEnabledCallCount == 0)
        #expect(service.selectProviderCallCount == 0)
        #expect(service.saveProviderConfigurationCallCount == 0)
        #expect(service.triggerBackupIfNeededCallCount == 0)
        #expect(service.forceBackupCallCount == 0)
    }

    @Test
    func statusPublisher_updatesStatus() {
        let service = AutoBackupServiceMock(status: .disabled, configuration: .init())
        let sut = makeSUT(service: service)

        service.statusPublisherSubject.send(.backingUp)

        #expect(sut.status == .backingUp)
    }

    @Test
    func configurationPublisher_updatesConfiguration() {
        let service = AutoBackupServiceMock(status: .disabled, configuration: .init())
        let sut = makeSUT(service: service)

        var newConfiguration = AutoBackupConfiguration()
        newConfiguration.isEnabled = true
        service.configurationPublisherSubject.send(newConfiguration)

        #expect(sut.configuration == newConfiguration)
    }

    @Test
    func refreshProviderStates_mapsAvailableProviders() async {
        let provider = BackupStorageProviderMock(
            id: "provider-1",
            displayName: "Files",
            iconSystemName: "folder",
            isConfigured: true,
            configurationSummary: "Vault Backups",
        )
        let service = AutoBackupServiceMock(
            status: .disabled,
            configuration: .init(),
            availableProviders: [provider],
        )
        let sut = makeSUT(service: service)

        await sut.refreshProviderStates()

        #expect(sut.providerStates == [
            .init(
                id: "provider-1",
                displayName: "Files",
                iconSystemName: "folder",
                isConfigured: true,
                folderSummary: "Vault Backups",
            ),
        ])
    }

    @Test
    func onAppear_refreshesProviderStatesWhenNotSeeded() async {
        let provider = BackupStorageProviderMock(id: "provider-1", displayName: "Files")
        let service = AutoBackupServiceMock(
            status: .disabled,
            configuration: .init(),
            availableProviders: [provider],
        )
        let sut = makeSUT(service: service)

        await sut.onAppear()

        #expect(sut.providerStates.map(\.id) == ["provider-1"])
    }

    @Test
    func onAppear_keepsSeededProviderStates() async {
        let service = AutoBackupServiceMock(status: .disabled, configuration: .init())
        let sut = makeSUT(service: service, initialProviderStates: [anyProviderState(id: "provider-1")])

        await sut.onAppear()

        #expect(sut.providerStates.map(\.id) == ["provider-1"])
    }

    @Test
    func activeProvider_prefersConfiguredProviderIDOverFirst() {
        var configuration = AutoBackupConfiguration()
        configuration.providerID = "provider-2"
        let service = AutoBackupServiceMock(status: .disabled, configuration: configuration)

        let sut = makeSUT(service: service, initialProviderStates: [
            anyProviderState(id: "provider-1"),
            anyProviderState(id: "provider-2"),
        ])

        #expect(sut.activeProvider?.id == "provider-2")
    }

    @Test
    func activeProvider_fallsBackToFirstWhenNoProviderSelected() {
        let service = AutoBackupServiceMock(status: .disabled, configuration: .init())

        let sut = makeSUT(service: service, initialProviderStates: [
            anyProviderState(id: "provider-1"),
            anyProviderState(id: "provider-2"),
        ])

        #expect(sut.activeProvider?.id == "provider-1")
    }

    @Test
    func beginDestinationSelection_selectsActiveProviderAndClearsError() async {
        let service = AutoBackupServiceMock(status: .disabled, configuration: .init())
        let sut = makeSUT(service: service, initialProviderStates: [anyProviderState(id: "provider-1")])
        sut.configureError = .accessDenied

        await sut.beginDestinationSelection()

        #expect(service.selectProviderCallCount == 1)
        #expect(service.selectProviderArgValues == ["provider-1"])
        #expect(sut.configureError == nil)
    }

    @Test
    func configureDestination_successConfiguresSavesAndTriggersBackup() async {
        let provider = BackupStorageProviderMock(id: "provider-1")
        let service = AutoBackupServiceMock(
            status: .disabled,
            configuration: .init(),
            availableProviders: [provider],
        )
        let sut = makeSUT(service: service, initialProviderStates: [anyProviderState(id: "provider-1")])

        await sut.configureDestination(url: anyFolderURL())

        #expect(provider.configureCallCount == 1)
        #expect(service.saveProviderConfigurationCallCount == 1)
        #expect(service.triggerBackupIfNeededCallCount == 1)
        #expect(sut.configureError == nil)
    }

    @Test
    func configureDestination_failureSurfacesErrorAndDoesNotSaveOrTrigger() async {
        let provider = BackupStorageProviderMock(id: "provider-1")
        provider.configureHandler = { _ in throw AutoBackupError.accessDenied }
        let service = AutoBackupServiceMock(
            status: .disabled,
            configuration: .init(),
            availableProviders: [provider],
        )
        let sut = makeSUT(service: service, initialProviderStates: [anyProviderState(id: "provider-1")])

        await sut.configureDestination(url: anyFolderURL())

        #expect(sut.configureError == .accessDenied)
        #expect(service.saveProviderConfigurationCallCount == 0)
        #expect(service.triggerBackupIfNeededCallCount == 0)
    }

    @Test
    func configureDestination_unknownFailureMapsToUnknownError() async {
        struct SomeError: Error {}
        let provider = BackupStorageProviderMock(id: "provider-1")
        provider.configureHandler = { _ in throw SomeError() }
        let service = AutoBackupServiceMock(
            status: .disabled,
            configuration: .init(),
            availableProviders: [provider],
        )
        let sut = makeSUT(service: service, initialProviderStates: [anyProviderState(id: "provider-1")])

        await sut.configureDestination(url: anyFolderURL())

        guard case .unknown = sut.configureError else {
            Issue.record("Expected .unknown, got \(String(describing: sut.configureError))")
            return
        }
    }

    @Test
    func setEnabled_forwardsToService() async {
        let service = AutoBackupServiceMock(status: .disabled, configuration: .init())
        let sut = makeSUT(service: service)

        await sut.setEnabled(true)

        #expect(service.setEnabledCallCount == 1)
        #expect(service.setEnabledArgValues == [true])
    }

    @Test
    func setRetention_forwardsToService() async {
        let service = AutoBackupServiceMock(status: .disabled, configuration: .init())
        let sut = makeSUT(service: service)

        await sut.setRetention(.days7)

        #expect(service.setRetentionCallCount == 1)
    }

    @Test
    func backupNow_forcesBackup() async {
        let service = AutoBackupServiceMock(status: .disabled, configuration: .init())
        let sut = makeSUT(service: service)

        await sut.backupNow()

        #expect(service.forceBackupCallCount == 1)
    }

    @Test
    func isBackingUp_trueOnlyWhileWorking() {
        let service = AutoBackupServiceMock(status: .disabled, configuration: .init())
        let sut = makeSUT(service: service)

        service.statusPublisherSubject.send(.backingUp)
        #expect(sut.isBackingUp)

        service.statusPublisherSubject.send(.cleaningUp)
        #expect(sut.isBackingUp)

        service.statusPublisherSubject.send(.idle)
        #expect(!sut.isBackingUp)
    }

    @Test
    func footerText_explainsFeatureWhenDisabled() {
        let service = AutoBackupServiceMock(status: .disabled, configuration: .init())
        let sut = makeSUT(service: service)

        #expect(sut.footerText.contains("Enable to automatically back up"))
    }

    @Test
    func footerText_carriesLiveStatusWhenEnabled() {
        var configuration = AutoBackupConfiguration()
        configuration.isEnabled = true
        let service = AutoBackupServiceMock(status: .backingUp, configuration: configuration)
        let sut = makeSUT(service: service)

        #expect(sut.footerText == sut.statusDescription)
    }
}

// MARK: - Helpers

extension AutoBackupViewModelTests {
    private func makeSUT(
        service: AutoBackupServiceMock,
        initialProviderStates: [AutoBackupViewModel.ProviderDisplayState] = [],
    ) -> AutoBackupViewModel {
        AutoBackupViewModel(service: service, initialProviderStates: initialProviderStates)
    }

    private func anyProviderState(
        id: String,
        isConfigured: Bool = false,
    ) -> AutoBackupViewModel.ProviderDisplayState {
        .init(
            id: id,
            displayName: "Files",
            iconSystemName: "folder",
            isConfigured: isConfigured,
            folderSummary: isConfigured ? "Vault Backups" : nil,
        )
    }

    private func anyFolderURL() -> URL {
        URL(fileURLWithPath: "/tmp/backups", isDirectory: true)
    }
}
