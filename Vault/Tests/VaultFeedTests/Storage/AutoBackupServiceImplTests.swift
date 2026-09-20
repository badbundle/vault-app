import Combine
import Foundation
import TestHelpers
import Testing
import VaultCore
@testable import VaultFeed

@MainActor
struct AutoBackupServiceImplTests {
    // MARK: - Init

    @Test @LeakTracked
    func init_defaultsToDisabledStatus() throws {
        let sut = try makeSUT()

        #expect(sut.configuration.isEnabled == false)
    }

    @Test @LeakTracked
    func init_restoresConfigurationFromDefaults() throws {
        let defaults = try testUserDefaults()
        let config = AutoBackupConfiguration(
            isEnabled: true,
            retentionDays: .year1,
            providerID: "test-provider",
            providerConfigs: [:],
            lastBackupHash: "abc123",
            lastBackupDate: Date(timeIntervalSince1970: 1000),
        )
        let wrappedDefaults = Defaults(userDefaults: defaults)
        try wrappedDefaults.set(config, for: Key<AutoBackupConfiguration>(VaultIdentifiers.AutoBackup.configuration))

        let sut = try makeSUT(defaults: defaults)

        #expect(sut.configuration.isEnabled == true)
        #expect(sut.configuration.retentionDays == .year1)
        #expect(sut.configuration.providerID == "test-provider")
        #expect(sut.configuration.lastBackupHash == "abc123")
    }

    // MARK: - Set Enabled

    @Test @LeakTracked
    func setEnabled_updatesConfiguration() async throws {
        let sut = try makeSUT()

        await sut.setEnabled(true)

        #expect(sut.configuration.isEnabled == true)
    }

    @Test @LeakTracked
    func setEnabled_false_setsStatusToDisabled() async throws {
        let sut = try makeSUT()
        await sut.setEnabled(true)

        await sut.setEnabled(false)

        #expect(sut.status == .disabled)
    }

    @Test @LeakTracked
    func setEnabled_true_setsStatusToIdle_whenNoLastBackup() async throws {
        let provider = BackupStorageProviderStub(id: "test", isConfigured: false)
        let sut = try makeSUT(providers: [provider])
        await sut.selectProvider(id: "test")

        await sut.setEnabled(true)

        #expect(sut.status == .idle)
    }

    @Test @LeakTracked
    func setEnabled_persistsToDefaults() async throws {
        let defaults = try testUserDefaults()
        let sut = try makeSUT(defaults: defaults)

        await sut.setEnabled(true)

        let wrappedDefaults = Defaults(userDefaults: defaults)
        let saved = wrappedDefaults.get(for: Key<AutoBackupConfiguration>(VaultIdentifiers.AutoBackup.configuration))
        #expect(saved?.isEnabled == true)
    }

    // MARK: - Select Provider

    @Test @LeakTracked
    func selectProvider_updatesConfiguration() async throws {
        let provider = BackupStorageProviderStub(id: "icloud")
        let sut = try makeSUT(providers: [provider])

        await sut.selectProvider(id: "icloud")

        #expect(sut.configuration.providerID == "icloud")
        #expect(sut.selectedProvider?.id == "icloud")
    }

    @Test @LeakTracked
    func selectedProvider_returnsNil_whenNoProviderSelected() throws {
        let sut = try makeSUT()

        #expect(sut.selectedProvider == nil)
    }

    @Test @LeakTracked
    func selectedProvider_returnsNil_whenProviderIDDoesNotMatch() throws {
        let provider = BackupStorageProviderStub(id: "icloud")
        let sut = try makeSUT(providers: [provider])

        #expect(sut.selectedProvider == nil)
    }

    // MARK: - Set Retention

    @Test @LeakTracked
    func setRetention_updatesConfiguration() async throws {
        let sut = try makeSUT()

        await sut.setRetention(.year1)

        #expect(sut.configuration.retentionDays == .year1)
    }

    @Test @LeakTracked
    func setRetention_persistsToDefaults() async throws {
        let defaults = try testUserDefaults()
        let sut = try makeSUT(defaults: defaults)

        await sut.setRetention(.days7)

        let wrappedDefaults = Defaults(userDefaults: defaults)
        let saved = wrappedDefaults.get(for: Key<AutoBackupConfiguration>(VaultIdentifiers.AutoBackup.configuration))
        #expect(saved?.retentionDays == .days7)
    }

    // MARK: - Available Providers

    @Test @LeakTracked
    func availableProviders_returnsInjectedProviders() throws {
        let providers = [
            BackupStorageProviderStub(id: "a"),
            BackupStorageProviderStub(id: "b"),
        ]
        let sut = try makeSUT(providers: providers)

        #expect(sut.availableProviders.count == 2)
        #expect(sut.availableProviders.map(\.id) == ["a", "b"])
    }

    // MARK: - Trigger Backup If Needed

    @Test @LeakTracked
    func triggerBackupIfNeeded_doesNothing_whenDisabled() async throws {
        let provider = BackupStorageProviderStub(id: "test")
        let sut = try makeSUT(providers: [provider])
        await sut.selectProvider(id: "test")

        await sut.triggerBackupIfNeeded()

        #expect(provider.writeCallCount == 0)
    }

    @Test @LeakTracked
    func triggerBackupIfNeeded_doesNothing_whenNoProviderSelected() async throws {
        let sut = try makeSUT()
        await sut.setEnabled(true)

        await sut.triggerBackupIfNeeded()

        #expect(sut.status == .idle)
    }

    @Test @LeakTracked
    func triggerBackupIfNeeded_doesNothing_whenProviderNotConfigured() async throws {
        let provider = BackupStorageProviderStub(id: "test", isConfigured: false)
        let sut = try makeSUT(providers: [provider])
        await sut.selectProvider(id: "test")
        await sut.setEnabled(true)

        await sut.triggerBackupIfNeeded()

        #expect(provider.writeCallCount == 0)
    }

    @Test @LeakTracked
    func triggerBackupIfNeeded_runsAfterKillphraseDeletionChangesHash() async throws {
        let provider = BackupStorageProviderStub(id: "test")
        let store = VaultStoreStub()
        let killphraseDeleter = VaultStoreKillphraseDeleterMock()
        let dataModel = anyVaultDataModel(vaultStore: store, vaultKillphraseDeleter: killphraseDeleter)
        try await dataModel.store(backupPassword: anyBackupPassword())
        await dataModel.setup()
        let sut = try makeSUT(providers: [provider], dataModel: dataModel)
        await Task.yield()
        await sut.setEnabled(true)
        await sut.selectProvider(id: "test")
        // Take a backup so lastBackupHash matches the current payload hash.
        await sut.forceBackup()
        #expect(provider.writeCallCount == 1)

        // Killphrase fires: the store's contents change out from under
        // the model, and the payload hash must be refreshed on that path
        // or this trigger compares the stale hash and skips — leaving the
        // killed items recoverable from the newest backup.
        killphraseDeleter.deleteItemsHandler = { _, _ in true }
        dataModel.itemsSearchQuery = "kill phrase"
        store.exportVaultHandler = { userDescription in
            .init(userDescription: userDescription, items: [uniqueVaultItem()], tags: [])
        }
        await dataModel.reloadItems()

        await sut.triggerBackupIfNeeded()

        #expect(provider.writeCallCount == 2)
    }

    // MARK: - Force Backup

    @Test @LeakTracked
    func forceBackup_setsErrorStatus_whenNoProviderSelected() async throws {
        let sut = try makeSUT()

        await sut.forceBackup()

        #expect(sut.status == .error(.noProviderSelected))
    }

    @Test @LeakTracked
    func forceBackup_setsErrorStatus_whenProviderNotConfigured() async throws {
        let provider = BackupStorageProviderStub(id: "test", isConfigured: false)
        let sut = try makeSUT(providers: [provider])
        await sut.selectProvider(id: "test")

        await sut.forceBackup()

        #expect(sut.status == .error(.providerNotConfigured))
    }

    @Test @LeakTracked
    func forceBackup_setsErrorStatus_whenProviderNotAvailable() async throws {
        let provider = BackupStorageProviderStub(id: "test", isAvailable: false)
        let sut = try makeSUT(providers: [provider])
        await sut.selectProvider(id: "test")

        await sut.forceBackup()

        #expect(sut.status == .error(.providerUnavailable(reason: "Provider is not available")))
    }

    @Test @LeakTracked
    func forceBackup_setsErrorStatus_whenBackupPasswordNotSet() async throws {
        let provider = BackupStorageProviderStub(id: "test")
        let sut = try makeSUT(providers: [provider])
        await sut.selectProvider(id: "test")

        await sut.forceBackup()

        #expect(sut.status == .error(.backupPasswordNotSet))
    }

    @Test @LeakTracked
    func forceBackup_writesPDFUpdatesConfigurationAndLogsEvent() async throws {
        let clock = EpochClockMock(currentTime: 100)
        let provider = BackupStorageProviderStub(id: "test")
        let store = VaultStoreStub()
        var exportDescriptions: [String] = []
        store.exportVaultHandler = { userDescription in
            exportDescriptions.append(userDescription)
            return .init(userDescription: userDescription, items: [uniqueVaultItem()], tags: [])
        }
        let dataModel = anyVaultDataModel(vaultStore: store)
        try await dataModel.store(backupPassword: anyBackupPassword())
        await dataModel.setup()
        let expectedHash = try #require(dataModel.currentPayloadHash)
        let logger = BackupEventLoggerMock()
        let sut = try makeSUT(
            clock: clock,
            providers: [provider],
            dataModel: dataModel,
            backupEventLogger: logger,
        )
        await Task.yield()
        await sut.setRetention(.forever)
        await sut.selectProvider(id: "test")

        await confirmation("Auto-backup event logged", expectedCount: 1) { confirmLog in
            logger.exportedToAutoBackupHandler = { date, hash, providerID in
                #expect(date == clock.currentDate)
                #expect(hash == expectedHash)
                #expect(providerID == "test")
                confirmLog()
            }

            await sut.forceBackup()
        }

        let written = try #require(provider.writtenData.first)
        let timestamp = VaultDateFormatter(timezone: .current).formatForFileName(date: clock.currentDate)
        #expect(provider.writeCallCount == 1)
        #expect(written.filename == "vault-auto-backup-\(timestamp).pdf")
        #expect(written.data.isNotEmpty)
        #expect(sut.configuration.lastBackupHash == expectedHash.value.base64EncodedString())
        #expect(sut.configuration.lastBackupDate == clock.currentDate)
        #expect(sut.status == .completed(clock.currentDate))
        #expect(logger.exportedToAutoBackupCallCount == 1)
        #expect(provider.listBackupsCallCount == 0)
        #expect(exportDescriptions == ["", "Auto-backup"])
    }

    @Test @LeakTracked
    func forceBackup_publishesOrderedProgressEndingInCompleted() async throws {
        let clock = EpochClockMock(currentTime: 100)
        let provider = BackupStorageProviderStub(id: "test")
        let dataModel = anyVaultDataModel()
        try await dataModel.store(backupPassword: anyBackupPassword())
        await dataModel.setup()
        let sut = try makeSUT(clock: clock, providers: [provider], dataModel: dataModel)
        await Task.yield()
        await sut.setRetention(.forever)
        await sut.selectProvider(id: "test")
        var statuses = [AutoBackupStatus]()
        var bag = Set<AnyCancellable>()
        sut.statusPublisher.sink { statuses.append($0) }.store(in: &bag)

        await sut.forceBackup()

        let progress = statuses.compactMap { status -> AutoBackupProgress? in
            if case let .backingUp(progress) = status {
                progress
            } else {
                nil
            }
        }
        #expect(statuses.first == .backingUp(.starting))
        #expect(statuses.last == .completed(clock.currentDate))
        #expect(statuses.count == progress.count + 1, "Only progress precedes completion")
        let fractions = progress.map(\.fractionCompleted)
        #expect(fractions == fractions.sorted(), "Progress never goes backwards")
        #expect(progress.contains(.init(phase: .rendering, phaseFraction: 1)), "Rendering is reported complete")
        #expect(progress.last == .init(phase: .saving), "Saving is the final phase")
    }

    // MARK: - Cleanup Old Backups

    @Test @LeakTracked
    func cleanupOldBackups_doesNothing_whenRetentionIsForever() async throws {
        let provider = BackupStorageProviderStub(id: "test")
        let sut = try makeSUT(providers: [provider])
        await sut.selectProvider(id: "test")
        await sut.setRetention(.forever)

        await sut.cleanupOldBackups()

        #expect(provider.listBackupsCallCount == 0)
    }

    @Test @LeakTracked
    func cleanupOldBackups_doesNothing_whenNoProviderSelected() async throws {
        let sut = try makeSUT()

        await sut.cleanupOldBackups()

        #expect(sut.status == .disabled)
    }

    @Test @LeakTracked
    func cleanupOldBackups_deletesOldBackups() async throws {
        let clock = EpochClockMock(currentTime: Date(timeIntervalSince1970: 100 * 86400).timeIntervalSince1970)
        let provider = BackupStorageProviderStub(id: "test", backups: [
            BackupFileInfo(filename: "old.pdf", createdDate: Date(timeIntervalSince1970: 0), size: 100),
            BackupFileInfo(filename: "new.pdf", createdDate: Date(timeIntervalSince1970: 99 * 86400), size: 100),
        ])
        let sut = try makeSUT(clock: clock, providers: [provider])
        // Set retention before selecting provider to avoid cleanup running during setRetention
        await sut.setRetention(.days30)
        await sut.selectProvider(id: "test")

        await sut.cleanupOldBackups()

        #expect(provider.deletedFilenames == ["old.pdf"])
    }

    @Test @LeakTracked
    func cleanupOldBackups_setsErrorStatus_onFailure() async throws {
        let provider = BackupStorageProviderStub(id: "test", listBackupsError: TestError())
        let sut = try makeSUT(providers: [provider])
        await sut.selectProvider(id: "test")
        await sut.setRetention(.days7)

        await sut.cleanupOldBackups()

        if case .error(.cleanupFailed) = sut.status {
            // expected
        } else {
            Issue.record("Expected cleanupFailed error, got \(sut.status)")
        }
    }

    // MARK: - Notify Data Changed

    @Test @LeakTracked
    func notifyDataChanged_doesNothing_whenDisabled() throws {
        let sut = try makeSUT()

        sut.notifyDataChanged()

        // No crash, no status change
        #expect(sut.status == .disabled)
    }

    // MARK: - Status Publisher

    @Test @LeakTracked
    func statusPublisher_emitsOnStatusChange() async throws {
        let sut = try makeSUT()

        await confirmation { @MainActor confirmation in
            var bag = Set<AnyCancellable>()
            sut.statusPublisher.sink { status in
                if status == .disabled {
                    confirmation.confirm()
                }
            }.store(in: &bag)
            await sut.setEnabled(false)
        }
    }

    // MARK: - Configuration Publisher

    @Test @LeakTracked
    func configurationPublisher_emitsOnConfigChange() async throws {
        let sut = try makeSUT()

        await confirmation { @MainActor confirmation in
            var bag = Set<AnyCancellable>()
            sut.configurationPublisher.sink { config in
                if config.retentionDays == .year1 {
                    confirmation.confirm()
                }
            }.store(in: &bag)
            await sut.setRetention(.year1)
        }
    }

    // MARK: - Provider Configuration Persistence

    @Test @LeakTracked
    func saveProviderConfiguration_persistsProviderConfig() async throws {
        let defaults = try testUserDefaults()
        let configData = Data("test-config".utf8)
        let provider = BackupStorageProviderStub(id: "test", configurationData: configData)
        let sut = try makeSUT(defaults: defaults, providers: [provider])

        await sut.saveProviderConfiguration()

        let wrappedDefaults = Defaults(userDefaults: defaults)
        let saved = wrappedDefaults.get(for: Key<AutoBackupConfiguration>(VaultIdentifiers.AutoBackup.configuration))
        #expect(saved?.providerConfigs["test"] == configData)
    }

    @Test @LeakTracked
    func init_restoresProviderConfiguration() async throws {
        let defaults = try testUserDefaults()
        let configData = Data("restored-config".utf8)
        let config = AutoBackupConfiguration(
            isEnabled: false,
            retentionDays: .days30,
            providerID: nil,
            providerConfigs: ["test": configData],
            lastBackupHash: nil,
            lastBackupDate: nil,
        )
        let wrappedDefaults = Defaults(userDefaults: defaults)
        try wrappedDefaults.set(config, for: Key<AutoBackupConfiguration>(VaultIdentifiers.AutoBackup.configuration))

        let provider = BackupStorageProviderStub(id: "test")
        let sut = try makeSUT(defaults: defaults, providers: [provider])

        // Allow the init Task to run. SUT must stay alive until then because the restore Task
        // captures `self` weakly.
        await Task.yield()
        _ = sut

        #expect(provider.restoredConfigurationData == configData)
    }
}

// MARK: - Helpers

extension AutoBackupServiceImplTests {
    private func makeSUT(
        clock: EpochClockMock = EpochClockMock(currentTime: 100),
        defaults: UserDefaults? = nil,
        providers: [BackupStorageProviderStub] = [],
        dataModel: VaultDataModel? = nil,
        backupEventLogger: BackupEventLoggerMock? = nil,
    ) throws -> AutoBackupServiceImpl {
        let userDefaults = try defaults ?? testUserDefaults()
        let dataModel = trackForMemoryLeaks(dataModel ?? anyVaultDataModel())
        let backupEventLogger = trackForMemoryLeaks(backupEventLogger ?? BackupEventLoggerMock())
        trackForMemoryLeaks(clock)
        for provider in providers {
            trackForMemoryLeaks(provider)
        }
        return trackForMemoryLeaks(AutoBackupServiceImpl(
            dataModel: dataModel,
            backupEventLogger: backupEventLogger,
            clock: clock,
            defaults: Defaults(userDefaults: userDefaults),
            providers: providers,
        ))
    }
}

// MARK: - BackupStorageProviderStub

/// All access is from @MainActor test methods, so MainActor isolation is sufficient for Sendable.
@MainActor
final class BackupStorageProviderStub: BackupStorageProvider, Sendable {
    let id: String
    let displayName: String
    let iconSystemName: String

    private let _isConfigured: Bool
    private let _isAvailable: Bool
    private let _configurationData: Data?
    private let backups: [BackupFileInfo]
    private let listBackupsError: (any Error)?

    var isConfigured: Bool {
        _isConfigured
    }

    var isAvailable: Bool {
        _isAvailable
    }

    var configurationSummary: String? {
        _isConfigured ? "Test folder" : nil
    }

    var configurationData: Data? {
        _configurationData
    }

    private(set) var writeCallCount = 0
    private(set) var writtenData: [(data: Data, filename: String)] = []
    private(set) var deletedFilenames: [String] = []
    private(set) var listBackupsCallCount = 0
    private(set) var restoredConfigurationData: Data?
    private(set) var clearedConfiguration = false

    init(
        id: String,
        displayName: String = "Test Provider",
        iconSystemName: String = "folder",
        isConfigured: Bool = true,
        isAvailable: Bool = true,
        configurationData: Data? = nil,
        backups: [BackupFileInfo] = [],
        listBackupsError: (any Error)? = nil,
    ) {
        self.id = id
        self.displayName = displayName
        self.iconSystemName = iconSystemName
        _isConfigured = isConfigured
        _isAvailable = isAvailable
        _configurationData = configurationData
        self.backups = backups
        self.listBackupsError = listBackupsError
    }

    func restoreConfiguration(from data: Data) async throws {
        restoredConfigurationData = data
    }

    func clearConfiguration() async {
        clearedConfiguration = true
    }

    func configure(with _: URL) async throws {}

    func write(data: Data, filename: String) async throws {
        writeCallCount += 1
        writtenData.append((data: data, filename: filename))
    }

    func listBackups() async throws -> [BackupFileInfo] {
        listBackupsCallCount += 1
        if let error = listBackupsError {
            throw error
        }
        return backups
    }

    func delete(filename: String) async throws {
        deletedFilenames.append(filename)
    }
}
