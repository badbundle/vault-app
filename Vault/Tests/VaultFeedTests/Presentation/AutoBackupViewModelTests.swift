import Combine
import Foundation
import TestHelpers
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

        service.statusPublisherSubject.send(.backingUp(anyRun()))

        #expect(sut.status == .backingUp(anyRun()))
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
        #expect(!sut.hasLoadedProviderStates)

        await sut.onAppear()

        #expect(sut.providerStates.map(\.id) == ["provider-1"])
        #expect(sut.hasLoadedProviderStates)
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

        service.statusPublisherSubject.send(.backingUp(anyRun()))
        #expect(sut.isBackingUp)

        service.statusPublisherSubject.send(.cleaningUp)
        #expect(sut.isBackingUp)

        service.statusPublisherSubject.send(.idle)
        #expect(!sut.isBackingUp)
    }

    @Test
    func currentRun_isNilUnlessBackingUp() {
        let service = AutoBackupServiceMock(status: .idle, configuration: .init())
        let sut = makeSUT(service: service)

        #expect(sut.currentRun == nil)

        service.statusPublisherSubject.send(.cleaningUp)
        #expect(sut.currentRun == nil)

        service.statusPublisherSubject.send(.completed(Date()))
        #expect(sut.currentRun == nil)
    }

    @Test
    func currentRun_reflectsPublishedRun() {
        let service = AutoBackupServiceMock(status: .idle, configuration: .init())
        let sut = makeSUT(service: service)
        let run = anyRun(progress: .init(phase: .rendering, phaseFraction: 0.4))

        service.statusPublisherSubject.send(.backingUp(run))

        #expect(sut.currentRun == run)
    }

    @Test
    func lastBackupDate_prefersCompletedStatusOverConfiguration() {
        let configuration = enabledConfiguration(lastBackupDate: Date(timeIntervalSince1970: 100))
        let service = AutoBackupServiceMock(status: .idle, configuration: configuration)
        let sut = makeSUT(service: service)

        #expect(sut.lastBackupDate == Date(timeIntervalSince1970: 100))

        service.statusPublisherSubject.send(.completed(Date(timeIntervalSince1970: 200)))

        #expect(sut.lastBackupDate == Date(timeIntervalSince1970: 200))
    }

    @Test
    func destinationName_quotesConfiguredFolder() {
        let service = AutoBackupServiceMock(status: .idle, configuration: enabledConfiguration(providerID: "files"))
        let configured = makeSUT(
            service: service,
            initialProviderStates: [anyProviderState(id: "files", isConfigured: true)],
        )
        let unconfigured = makeSUT(
            service: service,
            initialProviderStates: [anyProviderState(id: "files", isConfigured: false)],
        )

        #expect(configured.destinationName == "“Vault Backups”")
        #expect(unconfigured.destinationName == "your backup folder")
    }

    @Test
    func scheduleSummary_describesRetention() {
        var configuration = enabledConfiguration()
        configuration.retentionDays = .days7
        let sut = makeSUT(service: AutoBackupServiceMock(status: .idle, configuration: configuration))

        #expect(sut.scheduleSummary.hasSuffix("Backups older than 7 days are deleted."))
    }

    @Test
    func scheduleSummary_saysBackupsAreKeptForever() {
        var configuration = enabledConfiguration()
        configuration.retentionDays = .forever
        let sut = makeSUT(service: AutoBackupServiceMock(status: .idle, configuration: configuration))

        #expect(sut.scheduleSummary.hasSuffix("Old backups are never deleted."))
    }

    @Test
    func statusPublisher_showsCompletionNoticeWhenBackupCompletes() {
        let service = AutoBackupServiceMock(status: .idle, configuration: .init())
        let sut = makeSUT(service: service)

        service.statusPublisherSubject.send(.backingUp(anyRun()))
        #expect(!sut.showsBackupCompleteNotice)

        service.statusPublisherSubject.send(.completed(Date()))
        #expect(sut.showsBackupCompleteNotice)
    }

    @Test
    func statusPublisher_keepsCompletionNoticeThroughCleanup() {
        let service = AutoBackupServiceMock(status: .idle, configuration: .init())
        let sut = makeSUT(service: service)

        service.statusPublisherSubject.send(.backingUp(anyRun()))
        service.statusPublisherSubject.send(.completed(Date()))
        service.statusPublisherSubject.send(.cleaningUp)
        service.statusPublisherSubject.send(.completed(Date()))

        #expect(sut.showsBackupCompleteNotice)
    }

    @Test
    func statusPublisher_doesNotShowCompletionNoticeWithoutABackup() {
        let service = AutoBackupServiceMock(status: .idle, configuration: .init())
        let sut = makeSUT(service: service)

        // Enabling the feature rests on the last backup date; changing retention cleans up and re-emits it.
        service.statusPublisherSubject.send(.completed(Date()))
        #expect(!sut.showsBackupCompleteNotice)

        service.statusPublisherSubject.send(.cleaningUp)
        service.statusPublisherSubject.send(.completed(Date()))
        #expect(!sut.showsBackupCompleteNotice)
    }

    @Test
    func statusPublisher_doesNotShowCompletionNoticeWhenBackupFails() {
        let service = AutoBackupServiceMock(status: .idle, configuration: .init())
        let sut = makeSUT(service: service)

        service.statusPublisherSubject.send(.backingUp(anyRun()))
        service.statusPublisherSubject.send(.error(.writeFailed(reason: "disk full")))
        #expect(!sut.showsBackupCompleteNotice)

        // The failed attempt must not be credited to a later, unrelated `.completed`.
        service.statusPublisherSubject.send(.completed(Date()))
        #expect(!sut.showsBackupCompleteNotice)
    }

    @Test
    func statusPublisher_hidesCompletionNoticeWhenNewBackupStarts() {
        let service = AutoBackupServiceMock(status: .idle, configuration: .init())
        let sut = makeSUT(service: service)
        service.statusPublisherSubject.send(.backingUp(anyRun()))
        service.statusPublisherSubject.send(.completed(Date()))
        #expect(sut.showsBackupCompleteNotice)

        service.statusPublisherSubject.send(.backingUp(anyRun()))

        #expect(!sut.showsBackupCompleteNotice)
    }

    @Test
    func statusPublisher_hidesCompletionNoticeAfterDuration() async throws {
        let service = AutoBackupServiceMock(status: .idle, configuration: .init())
        let sut = makeSUT(service: service, completionNoticeDuration: .milliseconds(1))
        service.statusPublisherSubject.send(.backingUp(anyRun()))
        service.statusPublisherSubject.send(.completed(Date()))
        #expect(sut.showsBackupCompleteNotice)

        try await sut.waitForChange(to: \.showsBackupCompleteNotice, timeout: .seconds(5)) {}

        #expect(!sut.showsBackupCompleteNotice)
    }

    // MARK: - Status Header

    @Test
    func statusHeader_isOffWhenDisabled() {
        // Even a stale error doesn't matter while auto-backup is off.
        let service = AutoBackupServiceMock(status: .error(.accessDenied), configuration: .init())
        let sut = makeSUT(service: service)

        #expect(sut.statusHeader.title == "Auto-Backup Is Off")
        #expect(sut.statusHeader.tone == .off)
    }

    @Test
    func statusHeader_asksForFolderWhenNoDestinationIsConfigured() {
        let service = AutoBackupServiceMock(status: .idle, configuration: enabledConfiguration())
        let sut = makeSUT(service: service, initialProviderStates: [anyProviderState(id: "files")])

        #expect(sut.statusHeader.title == "Choose a Folder")
        #expect(sut.statusHeader.tone == .attention)
    }

    @Test
    func statusHeader_doesNotAskForFolderBeforeProvidersHaveLoaded() {
        let service = AutoBackupServiceMock(status: .idle, configuration: enabledConfiguration())
        let sut = makeSUT(service: service)

        #expect(!sut.hasLoadedProviderStates)
        #expect(sut.statusHeader.title == "Auto-Backup Is On")
    }

    @Test
    func statusHeader_isOnWithLastBackupDate() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let service = AutoBackupServiceMock(
            status: .completed(date),
            configuration: enabledConfiguration(providerID: "files"),
        )
        let sut = makeSUT(service: service, initialProviderStates: [anyProviderState(id: "files", isConfigured: true)])

        #expect(sut.statusHeader.title == "Auto-Backup Is On")
        #expect(sut.statusHeader.subtitle.contains(date.formatted(date: .abbreviated, time: .shortened)))
        #expect(sut.statusHeader.tone == .healthy)
    }

    @Test
    func statusHeader_isOnAndNamesFolderBeforeFirstBackup() {
        let service = AutoBackupServiceMock(status: .idle, configuration: enabledConfiguration(providerID: "files"))
        let sut = makeSUT(service: service, initialProviderStates: [anyProviderState(id: "files", isConfigured: true)])

        #expect(sut.statusHeader.subtitle == "Your vault is saved to “Vault Backups” whenever it changes.")
    }

    @Test
    func statusHeader_isWorkingWhileBackingUp() {
        let service = AutoBackupServiceMock(status: .idle, configuration: enabledConfiguration(providerID: "files"))
        let sut = makeSUT(service: service, initialProviderStates: [anyProviderState(id: "files", isConfigured: true)])

        service.statusPublisherSubject.send(.backingUp(anyRun()))

        #expect(sut.statusHeader.title == "Backing Up")
        #expect(sut.statusHeader.subtitle.contains("“Vault Backups”"))
        #expect(sut.statusHeader.tone == .working)
    }

    /// Clean-up follows every backup and is usually over in a moment, so the headline doesn't flash for it.
    @Test
    func statusHeader_staysOnWhileCleaningUp() {
        let configuration = enabledConfiguration(providerID: "files", lastBackupDate: Date(timeIntervalSince1970: 100))
        let service = AutoBackupServiceMock(status: .idle, configuration: configuration)
        let sut = makeSUT(service: service, initialProviderStates: [anyProviderState(id: "files", isConfigured: true)])

        service.statusPublisherSubject.send(.cleaningUp)

        #expect(sut.statusHeader.title == "Auto-Backup Is On")
        #expect(sut.statusHeader.tone == .healthy)
    }

    @Test
    func statusHeader_explainsFailureAndHowToRecover() {
        let service = AutoBackupServiceMock(
            status: .error(.writeFailed(reason: "The folder could not be reached.")),
            configuration: enabledConfiguration(providerID: "files"),
        )
        let sut = makeSUT(service: service, initialProviderStates: [anyProviderState(id: "files", isConfigured: true)])

        #expect(sut.statusHeader.title == "Last Backup Failed")
        #expect(sut.statusHeader
            .subtitle == "Failed to save backup: The folder could not be reached. Please try again later.")
        #expect(sut.statusHeader.tone == .attention)
    }
}

// MARK: - Helpers

extension AutoBackupViewModelTests {
    private func makeSUT(
        service: AutoBackupServiceMock,
        initialProviderStates: [AutoBackupViewModel.ProviderDisplayState] = [],
        completionNoticeDuration: Duration = .seconds(2),
    ) -> AutoBackupViewModel {
        AutoBackupViewModel(
            service: service,
            initialProviderStates: initialProviderStates,
            completionNoticeDuration: completionNoticeDuration,
        )
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

    private func anyRun(progress: AutoBackupProgress = .starting) -> AutoBackupRun {
        AutoBackupRun(trigger: .automatic, startedAt: Date(timeIntervalSince1970: 1_700_000_000), progress: progress)
    }

    private func enabledConfiguration(
        providerID: String? = nil,
        lastBackupDate: Date? = nil,
    ) -> AutoBackupConfiguration {
        var configuration = AutoBackupConfiguration()
        configuration.isEnabled = true
        configuration.providerID = providerID
        configuration.lastBackupDate = lastBackupDate
        return configuration
    }

    private func anyFolderURL() -> URL {
        URL(fileURLWithPath: "/tmp/backups", isDirectory: true)
    }
}
