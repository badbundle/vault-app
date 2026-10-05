import Combine
import Foundation
import TestHelpers
import Testing
import VaultCore
@testable import VaultFeed

@MainActor
@Suite(.rendersPDFBackups)
struct AutoBackupServiceImplTests {
    // MARK: - Init

    /// Every saved backup is padded to a fixed size, so an auto-backup doesn't show how much its vault holds
    /// (VAULT-75). The tests below choose random padding only to be quick.
    @Test
    func init_padsBackupsToAFixedSizeByDefault() throws {
        let defaults = try Defaults(userDefaults: testUserDefaults())
        let sut = AutoBackupServiceImpl(
            dataModel: anyVaultDataModel(),
            backupEventLogger: BackupEventLoggerMock(),
            clock: EpochClockMock(currentTime: 100),
            defaults: defaults,
            providers: [],
        )

        #expect(sut.padding == .toFixedSize)
    }

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

    // MARK: - Forgetting

    /// After an erase, auto-backup mustn't remember where the erased vault's backups went: not in memory, where the
    /// service read it at launch, and not in its providers. The erase clears what's stored (`VaultEraser`).
    @Test @LeakTracked
    func forgetConfiguration_turnsItOffAndForgetsTheProviderEverywhere() async throws {
        let defaults = try testUserDefaults()
        let key = Key<AutoBackupConfiguration>(VaultIdentifiers.AutoBackup.configuration)
        try Defaults(userDefaults: defaults).set(
            AutoBackupConfiguration(
                isEnabled: true,
                retentionDays: .year1,
                providerID: "test-provider",
                providerConfigs: ["test-provider": Data("folder".utf8)],
                lastBackupHash: "abc123",
                lastBackupDate: Date(timeIntervalSince1970: 1000),
            ),
            for: key,
        )
        let provider = BackupStorageProviderStub(id: "test-provider")
        let sut = try makeSUT(defaults: defaults, providers: [provider])

        await sut.forgetConfiguration()

        #expect(sut.configuration == AutoBackupConfiguration())
        #expect(sut.status == .disabled)
        #expect(sut.selectedProvider == nil)
        #expect(provider.clearedConfiguration)
    }

    /// A backup being written when the vault is erased records nothing, and shows nothing, and nothing is backed up
    /// until the next vault opens.
    @Test @LeakTracked
    func forgetConfiguration_duringABackup_recordsNothingAndBacksUpNothingUntilTheNextVault() async throws {
        let storage = TwoVaultConfigurationStorage(first: .backingUp(providerConfig: "first"))
        let provider = BackupStorageProviderStub(id: "test")
        let logger = BackupEventLoggerMock()
        let sut = try await makeSUT(
            storage: storage,
            providers: [provider],
            dataModel: readyDataModel(),
            backupEventLogger: logger,
        )
        let writeStarted = Pending<Void>.signal()
        let releaseWrite = Pending<Void>.signal()
        provider.writeHandler = { _, _ in
            await writeStarted.fulfill()
            try await releaseWrite.wait()
        }
        let backup = Task { await sut.forceBackup() }
        try await writeStarted.wait()

        // The erase locks the session, then forgets the settings.
        storage.open(nil)
        await sut.forgetConfiguration()
        await releaseWrite.fulfill()
        await backup.value
        provider.writeHandler = nil
        await sut.triggerBackupIfNeeded()

        #expect(provider.writeCallCount == 1)
        #expect(provider.events.last == "clear")
        #expect(logger.exportedToAutoBackupCallCount == 0)
        #expect(storage.saved[0] == .backingUp(providerConfig: "first"))
        #expect(sut.configuration == AutoBackupConfiguration())
        #expect(sut.status == .disabled)
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

    @Test @LeakTracked
    func triggerBackupIfNeeded_reportsAutomaticRun() async throws {
        let clock = EpochClockMock(currentTime: 200)
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

        await sut.setEnabled(true)

        let runs = statuses.compactMap(backupRun)
        #expect(runs.isNotEmpty)
        #expect(runs.allSatisfy { $0.trigger == .automatic && $0.startedAt == clock.currentDate })
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
            logger.exportedToAutoBackupHandler = { date, hash, providerID, _ in
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
        // Kept forever, so it only looked for files that are gone.
        #expect(provider.listBackupsCallCount == 1)
        #expect(provider.deletedFilenames.isEmpty)
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

        let runs = statuses.compactMap(backupRun)
        let progress = runs.map(\.progress)
        #expect(statuses.first == .backingUp(.init(trigger: .manual, startedAt: clock.currentDate)))
        #expect(runs.allSatisfy { $0.trigger == .manual && $0.startedAt == clock.currentDate })
        #expect(statuses.last == .completed(clock.currentDate))
        #expect(statuses.count == progress.count + 1, "Only progress precedes completion")
        let fractions = progress.map(\.fractionCompleted)
        #expect(fractions == fractions.sorted(), "Progress never goes backwards")
        #expect(progress.contains(.init(phase: .rendering, phaseFraction: 1)), "Rendering is reported complete")
        #expect(progress.last == .init(phase: .saving), "Saving is the final phase")
    }

    @Test @LeakTracked
    func forceBackup_whileBackupInFlight_runsSequentially() async throws {
        let provider = BackupStorageProviderStub(id: "test")
        let dataModel = anyVaultDataModel()
        try await dataModel.store(backupPassword: anyBackupPassword())
        await dataModel.setup()
        let sut = try makeSUT(providers: [provider], dataModel: dataModel)
        await Task.yield()
        await sut.setRetention(.forever)
        await sut.selectProvider(id: "test")
        let firstWriteStarted = Pending<Void>.signal()
        let releaseFirstWrite = Pending<Void>.signal()
        provider.writeHandler = { _, _ in
            await firstWriteStarted.fulfill()
            try await releaseFirstWrite.wait()
        }

        var statuses = [AutoBackupStatus]()
        var bag = Set<AnyCancellable>()
        sut.statusPublisher.sink { statuses.append($0) }.store(in: &bag)

        let first = Task { await sut.forceBackup() }
        try await firstWriteStarted.wait()
        provider.writeHandler = nil
        let second = Task { await sut.forceBackup() }
        // Give the second backup every chance to run ahead of the first if it were allowed to.
        try await Task.sleep(for: .milliseconds(100))
        await releaseFirstWrite.fulfill()
        await first.value
        await second.value

        #expect(provider.writeCallCount == 2)
        let starts = statuses.indices.filter { backupRun(statuses[$0])?.progress == .starting }
        let completions = statuses.indices.filter {
            if case .completed = statuses[$0] {
                true
            } else {
                false
            }
        }
        #expect(starts.count == 2)
        #expect(completions.count == 2)
        #expect(
            try #require(completions.first) < #require(starts.last),
            "Second backup starts only after the first completes",
        )
    }

    @Test @LeakTracked
    func triggerBackupIfNeeded_whileBackupInFlight_rechecksHashAfterItFinishes() async throws {
        let provider = BackupStorageProviderStub(id: "test")
        let dataModel = anyVaultDataModel()
        try await dataModel.store(backupPassword: anyBackupPassword())
        await dataModel.setup()
        let sut = try makeSUT(providers: [provider], dataModel: dataModel)
        await Task.yield()
        await sut.setEnabled(true)
        await sut.setRetention(.forever)
        await sut.selectProvider(id: "test")
        let firstWriteStarted = Pending<Void>.signal()
        let releaseFirstWrite = Pending<Void>.signal()
        provider.writeHandler = { _, _ in
            await firstWriteStarted.fulfill()
            try await releaseFirstWrite.wait()
        }

        let first = Task { await sut.forceBackup() }
        try await firstWriteStarted.wait()
        provider.writeHandler = nil
        let second = Task { await sut.triggerBackupIfNeeded() }
        // Give the trigger every chance to run ahead of the first backup if it were allowed to.
        try await Task.sleep(for: .milliseconds(100))
        await releaseFirstWrite.fulfill()
        await first.value
        await second.value

        #expect(provider.writeCallCount == 1, "Nothing changed while the first backup ran, so no second backup")
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
        let defaults = try testUserDefaults()
        try await Defaults(userDefaults: defaults).saveAutoBackupConfiguration(
            .written(["old.pdf", "new.pdf"]),
            for: 0,
        )
        let sut = try makeSUT(clock: clock, defaults: defaults, providers: [provider])
        // Set retention before selecting provider to avoid cleanup running during setRetention
        await sut.setRetention(.days30)
        await sut.selectProvider(id: "test")

        await sut.cleanupOldBackups()

        #expect(provider.deletedFilenames == ["old.pdf"])
        #expect(sut.configuration.backupFilenames == ["new.pdf"])
    }

    /// A backup is only made after the vault changes, so a shorter retention can find every backup past it. The
    /// newest this vault recorded making stays, however old; the older ones go.
    @Test @LeakTracked
    func setRetention_withNoNewerBackup_keepsTheNewestAndDeletesTheRestPastIt() async throws {
        let day: Double = 86400
        let clock = EpochClockMock(currentTime: 100 * day)
        let provider = BackupStorageProviderStub(id: "test", backups: [
            BackupFileInfo(filename: "oldest.pdf", createdDate: Date(timeIntervalSince1970: 0), size: 100),
            BackupFileInfo(filename: "newest.pdf", createdDate: Date(timeIntervalSince1970: 50 * day), size: 100),
            BackupFileInfo(filename: "older.pdf", createdDate: Date(timeIntervalSince1970: 10 * day), size: 100),
        ])
        let storage = TwoVaultConfigurationStorage(first: .written(["oldest.pdf", "older.pdf", "newest.pdf"]))
        let sut = makeSUT(clock: clock, storage: storage, providers: [provider])
        await sut.selectProvider(id: "test")

        await sut.setRetention(.days7)

        #expect(provider.deletedFilenames == ["oldest.pdf", "older.pdf"])
        #expect(provider.files.map(\.filename) == ["newest.pdf"])
        #expect(storage.saved[0].backupFilenames == ["newest.pdf"])
    }

    /// With only one backup, however far past the retention, it's kept.
    @Test @LeakTracked
    func cleanupOldBackups_keepsTheOnlyBackupHoweverOld() async throws {
        let clock = EpochClockMock(currentTime: 1000 * 86400)
        let provider = BackupStorageProviderStub(id: "test", backups: [
            BackupFileInfo(filename: "only.pdf", createdDate: Date(timeIntervalSince1970: 0), size: 100),
        ])
        let storage = TwoVaultConfigurationStorage(first: .written(["only.pdf"]))
        let sut = makeSUT(clock: clock, storage: storage, providers: [provider])
        await sut.setRetention(.days7)
        await sut.selectProvider(id: "test")

        await sut.cleanupOldBackups()

        #expect(provider.deletedFilenames.isEmpty)
        #expect(storage.saved[0].backupFilenames == ["only.pdf"])
    }

    /// Cleaning up after a backup keeps the one just made, and those still within the retention, and deletes the
    /// rest.
    @Test @LeakTracked
    func forceBackup_thenCleanup_keepsTheNewBackupAndDeletesOlderOnesByRetention() async throws {
        let day: Double = 86400
        let clock = EpochClockMock(currentTime: 100 * day)
        let provider = BackupStorageProviderStub(id: "test", backups: [
            BackupFileInfo(filename: "old.pdf", createdDate: Date(timeIntervalSince1970: 60 * day), size: 100),
            BackupFileInfo(filename: "recent.pdf", createdDate: Date(timeIntervalSince1970: 95 * day), size: 100),
        ])
        provider.clock = clock
        var configuration = AutoBackupConfiguration.backingUp(providerConfig: "folder", retention: .days30)
        configuration.backupFilenames = ["old.pdf", "recent.pdf"]
        let storage = TwoVaultConfigurationStorage(first: configuration)
        let sut = try await makeSUT(clock: clock, storage: storage, providers: [provider], dataModel: readyDataModel())
        let newFile = Self.filename(at: clock)

        await sut.forceBackup()

        #expect(provider.deletedFilenames == ["old.pdf"])
        #expect(provider.files.map(\.filename) == ["recent.pdf", newFile])
        #expect(storage.saved[0].backupFilenames == ["recent.pdf", newFile])
    }

    /// Only the files this vault's auto-backup wrote: never another vault's, one from before they were recorded,
    /// or one the user put there, however old (MANIFESTO C10).
    @Test @LeakTracked
    func cleanupOldBackups_deletesOnlyTheFilesThisVaultWrote() async throws {
        let clock = EpochClockMock(currentTime: Date(timeIntervalSince1970: 100 * 86400).timeIntervalSince1970)
        let old = Date(timeIntervalSince1970: 0)
        let provider = BackupStorageProviderStub(id: "test", backups: [
            BackupFileInfo(filename: "mine.pdf", createdDate: old, size: 100),
            BackupFileInfo(filename: "my-newest.pdf", createdDate: Date(timeIntervalSince1970: 99 * 86400), size: 100),
            BackupFileInfo(filename: "another-vaults.pdf", createdDate: old, size: 100),
            BackupFileInfo(filename: "the-users.pdf", createdDate: old, size: 100),
        ])
        let storage = TwoVaultConfigurationStorage(
            first: .written(["mine.pdf", "my-newest.pdf"]),
            second: .written(["another-vaults.pdf"]),
        )
        let sut = makeSUT(clock: clock, storage: storage, providers: [provider])
        await sut.setRetention(.days30)
        await sut.selectProvider(id: "test")

        await sut.cleanupOldBackups()

        #expect(provider.deletedFilenames == ["mine.pdf"])
        #expect(storage.saved[0].backupFilenames == ["my-newest.pdf"])
        #expect(storage.saved[1].backupFilenames == ["another-vaults.pdf"])
    }

    /// A file it wrote that isn't there any more, because the user deleted it, is forgotten.
    @Test @LeakTracked
    func cleanupOldBackups_forgetsFilesThatAreGone() async throws {
        let clock = EpochClockMock(currentTime: Date(timeIntervalSince1970: 100 * 86400).timeIntervalSince1970)
        let provider = BackupStorageProviderStub(id: "test", backups: [
            BackupFileInfo(filename: "kept.pdf", createdDate: Date(timeIntervalSince1970: 99 * 86400), size: 100),
        ])
        let storage = TwoVaultConfigurationStorage(
            first: .written(["gone.pdf", "kept.pdf"]),
        )
        let sut = makeSUT(clock: clock, storage: storage, providers: [provider])
        await sut.setRetention(.days30)
        await sut.selectProvider(id: "test")

        await sut.cleanupOldBackups()

        #expect(provider.deletedFilenames.isEmpty)
        #expect(storage.saved[0].backupFilenames == ["kept.pdf"])
    }

    /// A file that isn't listed is only forgotten once the provider says it's gone. One only in iCloud for now isn't
    /// listed, but it's there, and still to be cleaned up.
    @Test @LeakTracked
    func cleanupOldBackups_keepsAFileThatIsOnlyInTheCloud() async throws {
        let clock = EpochClockMock(currentTime: Date(timeIntervalSince1970: 100 * 86400).timeIntervalSince1970)
        let provider = BackupStorageProviderStub(id: "test")
        provider.filesOnlyInTheCloud = ["evicted.pdf"]
        let storage = TwoVaultConfigurationStorage(first: .written(["evicted.pdf", "gone.pdf"]))
        let sut = makeSUT(clock: clock, storage: storage, providers: [provider])
        await sut.setRetention(.days30)
        await sut.selectProvider(id: "test")

        await sut.cleanupOldBackups()

        #expect(storage.saved[0].backupFilenames == ["evicted.pdf"])
        #expect(provider.deletedFilenames.isEmpty)
    }

    /// Kept forever, nothing is deleted, but files that are gone are forgotten, so the list doesn't grow without end.
    @Test @LeakTracked
    func cleanupOldBackups_keepingBackupsForever_deletesNothingButForgetsFilesThatAreGone() async throws {
        let clock = EpochClockMock(currentTime: Date(timeIntervalSince1970: 100 * 86400).timeIntervalSince1970)
        let provider = BackupStorageProviderStub(id: "test", backups: [
            BackupFileInfo(filename: "old.pdf", createdDate: Date(timeIntervalSince1970: 0), size: 100),
        ])
        let storage = TwoVaultConfigurationStorage(first: .written(["old.pdf", "gone.pdf"]))
        let sut = makeSUT(clock: clock, storage: storage, providers: [provider])
        await sut.setRetention(.forever)
        await sut.selectProvider(id: "test")
        let status = sut.status

        await sut.cleanupOldBackups()

        #expect(provider.deletedFilenames.isEmpty)
        #expect(storage.saved[0].backupFilenames == ["old.pdf"])
        #expect(sut.status == status)
    }

    /// With nothing recorded, there's nothing to clean up, and the folder isn't read.
    @Test @LeakTracked
    func cleanupOldBackups_withNoFilesRecorded_readsNothing() async throws {
        let provider = BackupStorageProviderStub(id: "test", backups: [
            BackupFileInfo(filename: "not-mine.pdf", createdDate: Date(timeIntervalSince1970: 0), size: 100),
        ])
        let sut = makeSUT(storage: TwoVaultConfigurationStorage(), providers: [provider])
        await sut.setRetention(.days7)
        await sut.selectProvider(id: "test")

        await sut.cleanupOldBackups()

        #expect(provider.listBackupsCallCount == 0)
        #expect(provider.deletedFilenames.isEmpty)
    }

    @Test @LeakTracked
    func cleanupOldBackups_setsErrorStatus_onFailure() async throws {
        let provider = BackupStorageProviderStub(id: "test", listBackupsError: TestError())
        let sut = makeSUT(storage: TwoVaultConfigurationStorage(first: .written(["mine.pdf"])), providers: [provider])
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

// MARK: - Each vault's own backups

extension AutoBackupServiceImplTests {
    @Test @LeakTracked
    func vaultDidChange_switchesToTheOpenVaultsConfigurationAndDestination() async throws {
        let second = AutoBackupConfiguration.backingUp(providerConfig: "second", isEnabled: false)
        let storage = TwoVaultConfigurationStorage(first: .backingUp(providerConfig: "first"), second: second)
        let provider = BackupStorageProviderStub(id: "test")
        let sut = makeSUT(storage: storage, providers: [provider])

        storage.open(1)
        await sut.vaultDidChange()

        #expect(sut.configuration == second)
        #expect(provider.events == ["restore first", "clear", "restore second"])
        #expect(sut.status == .disabled)
    }

    /// While the app is locked there's no vault, so no configuration and no destination.
    @Test @LeakTracked
    func vaultDidChange_toNoVault_clearsTheDestinationAndTurnsOff() async throws {
        let storage = TwoVaultConfigurationStorage(first: .backingUp(providerConfig: "first"))
        let provider = BackupStorageProviderStub(id: "test")
        let sut = makeSUT(storage: storage, providers: [provider])

        storage.open(nil)
        await sut.vaultDidChange()

        #expect(sut.configuration == AutoBackupConfiguration())
        #expect(provider.events == ["restore first", "clear"])
        #expect(sut.status == .disabled)
    }

    @Test @LeakTracked
    func forceBackup_recordsTheFileItWroteInTheOpenVaultsConfigurationOnly() async throws {
        let clock = EpochClockMock(currentTime: 100)
        let storage = TwoVaultConfigurationStorage(first: .backingUp(providerConfig: "first"))
        let provider = BackupStorageProviderStub(id: "test")
        let dataModel = try await readyDataModel()
        let sut = makeSUT(clock: clock, storage: storage, providers: [provider], dataModel: dataModel)

        await sut.forceBackup()

        #expect(storage.saved[0].backupFilenames == [Self.filename(at: clock)])
        #expect(storage.saved[0].lastBackupDate == clock.currentDate)
        #expect(storage.saved[1] == AutoBackupConfiguration())
    }

    /// The vault changed while its backup was being made, so the backup could be of the vault that's open now. It
    /// mustn't go into the previous vault's destination, or be recorded in either vault.
    @Test @LeakTracked
    func forceBackup_whenTheVaultChangesWhileItIsMade_writesNothing() async throws {
        let first = AutoBackupConfiguration.backingUp(providerConfig: "first")
        let storage = TwoVaultConfigurationStorage(first: first)
        let provider = BackupStorageProviderStub(id: "test")
        let store = VaultStoreStub()
        store.exportVaultHandler = { userDescription in
            if userDescription == "Auto-backup" {
                storage.open(1)
            }
            return VaultApplicationPayload(userDescription: userDescription, items: [uniqueVaultItem()], tags: [])
        }
        let logger = BackupEventLoggerMock()
        let sut = try await makeSUT(
            storage: storage,
            providers: [provider],
            dataModel: readyDataModel(vaultStore: store),
            backupEventLogger: logger,
        )

        await sut.forceBackup()
        await sut.vaultDidChange()

        #expect(provider.writeCallCount == 0)
        #expect(logger.exportedToAutoBackupCallCount == 0)
        #expect(storage.saved == [first, AutoBackupConfiguration()])
        #expect(sut.status == .disabled)
    }

    /// The vault changed while its backup was being written: the file is the previous vault's, in its destination,
    /// and nothing about it goes into the vault that's open now.
    @Test @LeakTracked
    func forceBackup_whenTheVaultChangesWhileItIsWritten_recordsNothingInTheNextVault() async throws {
        let storage = TwoVaultConfigurationStorage(first: .backingUp(providerConfig: "first"))
        let provider = BackupStorageProviderStub(id: "test")
        provider.writeHandler = { _, _ in storage.open(1) }
        let logger = BackupEventLoggerMock()
        let sut = try await makeSUT(
            storage: storage,
            providers: [provider],
            dataModel: readyDataModel(),
            backupEventLogger: logger,
        )

        await sut.forceBackup()

        #expect(provider.writeCallCount == 1)
        #expect(logger.exportedToAutoBackupCallCount == 0)
        #expect(storage.saved[1] == AutoBackupConfiguration())
    }

    /// The previous vault's destination is cleared at once, and the next vault's isn't set up until the backup of
    /// the previous vault has finished, so that backup can't write into it. Meanwhile, what's shown is the next
    /// vault's, and nothing of the backup underway.
    @Test @LeakTracked
    func vaultDidChange_waitsForTheBackupUnderwayBeforeSettingUpTheNextDestination() async throws {
        let storage = TwoVaultConfigurationStorage(
            first: .backingUp(providerConfig: "first"),
            second: .backingUp(providerConfig: "second"),
        )
        let provider = BackupStorageProviderStub(id: "test")
        let sut = try await makeSUT(storage: storage, providers: [provider], dataModel: readyDataModel())
        let writeStarted = Pending<Void>.signal()
        let releaseWrite = Pending<Void>.signal()
        provider.writeHandler = { _, _ in
            await writeStarted.fulfill()
            try await releaseWrite.wait()
        }
        var statuses = [AutoBackupStatus]()
        var bag = Set<AnyCancellable>()

        let backup = Task { await sut.forceBackup() }
        try await writeStarted.wait()
        storage.open(1)
        let change = Task { await sut.vaultDidChange() }
        // Give the change every chance to set up the next destination if it were allowed to.
        try await Task.sleep(for: .milliseconds(100))
        let filename = try #require(provider.writtenData.first?.filename)
        #expect(provider.events == ["restore first", "write \(filename)", "clear"])
        #expect(sut.configuration == storage.saved[1])
        #expect(sut.status == .idle)
        sut.statusPublisher.sink { statuses.append($0) }.store(in: &bag)

        await releaseWrite.fulfill()
        await backup.value
        await change.value

        #expect(provider.events == ["restore first", "write \(filename)", "clear", "restore second"])
        #expect(sut.configuration == storage.saved[1])
        #expect(statuses == [.idle], "Nothing of the previous vault's backup shows")
        #expect(storage.saved[1].backupFilenames.isEmpty)
    }

    /// A change saved while the vault is changing keeps the destination the vault had: the providers hold none of
    /// its own until they're set up again.
    @Test @LeakTracked
    func saveConfiguration_whileTheVaultIsChanging_keepsItsDestination() async throws {
        let second = AutoBackupConfiguration.backingUp(providerConfig: "second")
        let storage = TwoVaultConfigurationStorage(first: .backingUp(providerConfig: "first"), second: second)
        let provider = BackupStorageProviderStub(id: "test")
        let sut = try await makeSUT(storage: storage, providers: [provider], dataModel: readyDataModel())
        let writeStarted = Pending<Void>.signal()
        let releaseWrite = Pending<Void>.signal()
        provider.writeHandler = { _, _ in
            await writeStarted.fulfill()
            try await releaseWrite.wait()
        }
        let backup = Task { await sut.forceBackup() }
        try await writeStarted.wait()
        storage.open(1)
        let change = Task { await sut.vaultDidChange() }
        try await Task.sleep(for: .milliseconds(100))

        await sut.setRetention(.days7)

        #expect(storage.saved[1].providerConfigs == second.providerConfigs)
        #expect(storage.saved[1].retentionDays == .days7)
        await releaseWrite.fulfill()
        await backup.value
        await change.value
        #expect(provider.events.last == "restore second")
    }

    /// The name is taken, perhaps by another vault's backup made the same minute: it's left as it is, and the
    /// backup is written under another name.
    @Test @LeakTracked
    func forceBackup_whenItsFilenameIsTaken_writesAnotherFileAndLeavesThatOne() async throws {
        let clock = EpochClockMock(currentTime: 100)
        let taken = BackupFileInfo(filename: Self.filename(at: clock), createdDate: Date(), size: 1)
        let storage = TwoVaultConfigurationStorage(first: .backingUp(providerConfig: "first"))
        let provider = BackupStorageProviderStub(id: "test", backups: [taken])
        let sut = try await makeSUT(clock: clock, storage: storage, providers: [provider], dataModel: readyDataModel())

        await sut.forceBackup()

        let written = Self.filename(at: clock, suffix: "-2")
        #expect(provider.writtenData.map(\.filename) == [written])
        #expect(provider.files.map(\.filename) == [taken.filename, written])
        #expect(storage.saved[0].backupFilenames == [written])
        #expect(sut.status == .completed(clock.currentDate))
    }

    @Test @LeakTracked
    func forceBackup_whenEveryFilenameIsTaken_failsWithoutReplacingAny() async throws {
        let clock = EpochClockMock(currentTime: 100)
        let taken = ["", "-2", "-3", "-4", "-5"].map {
            BackupFileInfo(filename: Self.filename(at: clock, suffix: $0), createdDate: Date(), size: 1)
        }
        let storage = TwoVaultConfigurationStorage(first: .backingUp(providerConfig: "first"))
        let provider = BackupStorageProviderStub(id: "test", backups: taken)
        let sut = try await makeSUT(clock: clock, storage: storage, providers: [provider], dataModel: readyDataModel())

        await sut.forceBackup()

        #expect(provider.writeCallCount == 0)
        #expect(provider.files.map(\.filename) == taken.map(\.filename))
        #expect(storage.saved[0].backupFilenames.isEmpty)
        #expect(sut.status == .error(.backupFileExists))
    }

    /// The session has switched vault, and this hasn't caught up yet: cleaning up the previous vault's backups
    /// doesn't start.
    @Test @LeakTracked
    func cleanupOldBackups_afterTheVaultChanged_deletesNothing() async throws {
        let clock = EpochClockMock(currentTime: Date(timeIntervalSince1970: 100 * 86400).timeIntervalSince1970)
        let provider = BackupStorageProviderStub(id: "test", backups: [
            BackupFileInfo(filename: "mine.pdf", createdDate: Date(timeIntervalSince1970: 0), size: 100),
        ])
        let storage = TwoVaultConfigurationStorage(first: .written(["mine.pdf"]))
        let sut = makeSUT(clock: clock, storage: storage, providers: [provider])
        await sut.setRetention(.days30)
        await sut.selectProvider(id: "test")

        storage.open(1)
        await sut.cleanupOldBackups()

        #expect(provider.listBackupsCallCount == 0)
        #expect(provider.deletedFilenames.isEmpty)
    }

    /// The backup is logged into the vault it was made of, the one open when it started.
    @Test @LeakTracked
    func forceBackup_logsIntoTheVaultOpenWhenItStarted() async throws {
        let storage = TwoVaultConfigurationStorage(first: .backingUp(providerConfig: "first"))
        let provider = BackupStorageProviderStub(id: "test")
        let logger = BackupEventLoggerMock()
        logger.vaultToken = 7
        provider.writeHandler = { _, _ in logger.vaultToken = 8 }
        let sut = try await makeSUT(
            storage: storage,
            providers: [provider],
            dataModel: readyDataModel(),
            backupEventLogger: logger,
        )

        await sut.forceBackup()

        #expect(logger.exportedToAutoBackupArgValues.map(\.3) == [7])
    }

    /// Two vaults backing up to the same folder, in the same second, then cleaning up: each writes and deletes only
    /// its own files.
    @Test @LeakTracked
    func twoVaultsBackingUpToOneFolder_neverTouchEachOthersFiles() async throws {
        let day: Double = 86400
        let clock = EpochClockMock(currentTime: 1000 * day)
        let storage = TwoVaultConfigurationStorage(
            first: .backingUp(providerConfig: "folder", retention: .days7),
            second: .backingUp(providerConfig: "folder", retention: .days7),
        )
        let provider = BackupStorageProviderStub(id: "test")
        provider.clock = clock
        let sut = try await makeSUT(clock: clock, storage: storage, providers: [provider], dataModel: readyDataModel())
        let firstsFile = Self.filename(at: clock)
        let secondsFile = Self.filename(at: clock, suffix: "-2")

        await sut.forceBackup()
        storage.open(1)
        await sut.vaultDidChange()
        await sut.forceBackup()

        #expect(provider.files.map(\.filename) == [firstsFile, secondsFile])
        #expect(storage.saved[0].backupFilenames == [firstsFile])
        #expect(storage.saved[1].backupFilenames == [secondsFile])

        // Both files are past their retention by the time the second vault backs up again.
        clock.currentTime += 30 * day
        await sut.forceBackup()

        let secondsNewFile = Self.filename(at: clock)
        #expect(provider.deletedFilenames == [secondsFile])
        #expect(provider.files.map(\.filename) == [firstsFile, secondsNewFile])
        #expect(storage.saved[1].backupFilenames == [secondsNewFile])

        // The first vault's only backup is its newest, so cleaning up keeps it, however old.
        storage.open(0)
        await sut.vaultDidChange()
        await sut.cleanupOldBackups()

        #expect(provider.deletedFilenames == [secondsFile])
        #expect(provider.files.map(\.filename) == [firstsFile, secondsNewFile])
        #expect(storage.saved[0].backupFilenames == [firstsFile])
        #expect(storage.saved[1].backupFilenames == [secondsNewFile])
    }
}

// MARK: - Seeding the plain store's backup files

extension AutoBackupServiceImplTests {
    /// Cleaning up used to delete every auto-backup in the folder. The plain store's configuration from then records
    /// them all once, so they're still cleaned up.
    @Test @LeakTracked
    func vaultDidChange_withAPlainStoreConfigurationFromBeforeFilesWereRecorded_seedsThemFromTheFolder() async throws {
        let provider = BackupStorageProviderStub(id: "test", backups: [
            BackupFileInfo(filename: "vault-auto-backup-a.pdf", createdDate: Date(timeIntervalSince1970: 0), size: 1),
            BackupFileInfo(filename: "vault-auto-backup-b.pdf", createdDate: Date(timeIntervalSince1970: 0), size: 1),
        ])
        let storage = TwoVaultConfigurationStorage(first: .fromBeforeFilesWereRecorded, isDeviceWide: true)

        let sut = makeSUT(storage: storage, providers: [provider])
        await sut.vaultDidChange()

        #expect(storage.saved[0].backupFilenames == ["vault-auto-backup-a.pdf", "vault-auto-backup-b.pdf"])
        #expect(storage.saved[0].backupFilenamesAreComplete)
        #expect(sut.configuration == storage.saved[0])
    }

    /// It's seeded once: after that, a file only goes in the list when this configuration's auto-backup writes it.
    @Test @LeakTracked
    func seeding_happensOnce() async throws {
        let provider = BackupStorageProviderStub(id: "test", backups: [
            BackupFileInfo(filename: "vault-auto-backup-a.pdf", createdDate: Date(timeIntervalSince1970: 0), size: 1),
        ])
        let storage = TwoVaultConfigurationStorage(first: .fromBeforeFilesWereRecorded, isDeviceWide: true)
        let sut = makeSUT(storage: storage, providers: [provider])
        await sut.vaultDidChange()
        let listings = provider.listBackupsCallCount

        await sut.vaultDidChange()

        #expect(storage.saved[0].backupFilenames == ["vault-auto-backup-a.pdf"])
        #expect(provider.listBackupsCallCount == listings)
    }

    @Test @LeakTracked
    func seeding_thenCleaningUp_deletesTheOldBackupsTheOldCleanupWould() async throws {
        let clock = EpochClockMock(currentTime: Date(timeIntervalSince1970: 100 * 86400).timeIntervalSince1970)
        let provider = BackupStorageProviderStub(id: "test", backups: [
            BackupFileInfo(filename: "vault-auto-backup-old.pdf", createdDate: Date(timeIntervalSince1970: 0), size: 1),
            BackupFileInfo(
                filename: "vault-auto-backup-new.pdf",
                createdDate: Date(timeIntervalSince1970: 99 * 86400),
                size: 1,
            ),
        ])
        var legacy = AutoBackupConfiguration.fromBeforeFilesWereRecorded
        legacy.retentionDays = .days30
        let storage = TwoVaultConfigurationStorage(first: legacy, isDeviceWide: true)
        let sut = makeSUT(clock: clock, storage: storage, providers: [provider])
        await sut.vaultDidChange()

        await sut.cleanupOldBackups()

        #expect(provider.deletedFilenames == ["vault-auto-backup-old.pdf"])
        #expect(storage.saved[0].backupFilenames == ["vault-auto-backup-new.pdf"])
    }

    /// Never an encrypted vault's: the folder could hold another vault's backups.
    @Test @LeakTracked
    func seeding_neverHappensForAnEncryptedVault() async throws {
        let provider = BackupStorageProviderStub(id: "test", backups: [
            BackupFileInfo(filename: "vault-auto-backup-a.pdf", createdDate: Date(timeIntervalSince1970: 0), size: 1),
        ])
        var legacy = AutoBackupConfiguration.fromBeforeFilesWereRecorded
        legacy.retentionDays = .days7
        let storage = TwoVaultConfigurationStorage(first: legacy, isDeviceWide: false)
        let sut = makeSUT(storage: storage, providers: [provider])

        await sut.vaultDidChange()
        await sut.cleanupOldBackups()

        #expect(storage.saved[0] == legacy)
        #expect(provider.deletedFilenames.isEmpty)
    }

    /// If the folder can't be read, it's left to try again, the next time the vault opens or it cleans up.
    @Test @LeakTracked
    func seeding_whenTheFolderCannotBeRead_isLeftForLater() async throws {
        let storage = TwoVaultConfigurationStorage(first: .fromBeforeFilesWereRecorded, isDeviceWide: true)
        let unreadable = BackupStorageProviderStub(id: "test", listBackupsError: TestError())
        let sut = makeSUT(storage: storage, providers: [unreadable])

        await sut.vaultDidChange()

        #expect(!storage.saved[0].backupFilenamesAreComplete)
        #expect(!sut.configuration.backupFilenamesAreComplete)
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
            // Filling a fixed size is slow in tests, and these aren't about the padding.
            padding: .random,
        ))
    }

    private func makeSUT(
        clock: EpochClockMock = EpochClockMock(currentTime: 100),
        storage: TwoVaultConfigurationStorage,
        providers: [BackupStorageProviderStub] = [],
        dataModel: VaultDataModel? = nil,
        backupEventLogger: BackupEventLoggerMock? = nil,
    ) -> AutoBackupServiceImpl {
        let dataModel = trackForMemoryLeaks(dataModel ?? anyVaultDataModel())
        let backupEventLogger = trackForMemoryLeaks(backupEventLogger ?? BackupEventLoggerMock())
        trackForMemoryLeaks(clock)
        trackForMemoryLeaks(storage)
        for provider in providers {
            trackForMemoryLeaks(provider)
        }
        return trackForMemoryLeaks(AutoBackupServiceImpl(
            dataModel: dataModel,
            backupEventLogger: backupEventLogger,
            clock: clock,
            configurationStorage: storage,
            providers: providers,
            padding: .random,
        ))
    }

    /// A data model with a backup password, set up, so a backup can be made of it.
    private func readyDataModel(vaultStore: VaultStoreStub = VaultStoreStub()) async throws -> VaultDataModel {
        let dataModel = anyVaultDataModel(vaultStore: vaultStore)
        try await dataModel.store(backupPassword: anyBackupPassword())
        await dataModel.setup()
        return dataModel
    }

    private static func filename(at clock: EpochClockMock, suffix: String = "") -> String {
        let timestamp = VaultDateFormatter(timezone: .current).formatForFileName(date: clock.currentDate)
        return "vault-auto-backup-\(timestamp)\(suffix).pdf"
    }

    private func backupRun(_ status: AutoBackupStatus) -> AutoBackupRun? {
        if case let .backingUp(run) = status {
            run
        } else {
            nil
        }
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
    /// The destination it's set up with: as given, or as last restored. Clearing leaves an empty one, as a real
    /// provider's is.
    private var _configurationData: Data?
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
    /// The files in its folder: the ones it started with, and the ones written since.
    private(set) var files: [BackupFileInfo]
    /// What it was asked to do, in order.
    private(set) var events = [String]()
    /// Dates the files it writes, when it's set.
    var clock: EpochClockMock?

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
        files = backups
        self.listBackupsError = listBackupsError
    }

    func restoreConfiguration(from data: Data) async throws {
        restoredConfigurationData = data
        _configurationData = data
        events.append("restore \(String(decoding: data, as: UTF8.self))")
    }

    func clearConfiguration() async {
        clearedConfiguration = true
        _configurationData = Data("cleared".utf8)
        events.append("clear")
    }

    func configure(with _: URL) async throws {}

    /// Awaited after the write is recorded; lets a test hold a backup mid-flight.
    var writeHandler: ((Data, String) async throws -> Void)?

    /// Files that are there, but only in the cloud for now, so `listBackups()` doesn't list them.
    var filesOnlyInTheCloud = Set<String>()
    private(set) var containsBackupCallCount = 0

    /// Never replaces a file, as a real provider mustn't.
    func write(data: Data, filename: String) async throws {
        guard !has(filename) else { throw AutoBackupError.backupFileExists }
        writeCallCount += 1
        writtenData.append((data: data, filename: filename))
        files.append(BackupFileInfo(
            filename: filename,
            createdDate: clock?.currentDate ?? Date(),
            size: Int64(data.count),
        ))
        events.append("write \(filename)")
        try await writeHandler?(data, filename)
    }

    func listBackups() async throws -> [BackupFileInfo] {
        listBackupsCallCount += 1
        if let error = listBackupsError {
            throw error
        }
        return files
    }

    func containsBackup(filename: String) async throws -> Bool {
        containsBackupCallCount += 1
        return has(filename)
    }

    private func has(_ filename: String) -> Bool {
        files.contains { $0.filename == filename } || filesOnlyInTheCloud.contains(filename)
    }

    func delete(filename: String) async throws {
        deletedFilenames.append(filename)
        files.removeAll { $0.filename == filename }
        events.append("delete \(filename)")
    }
}

// MARK: - TwoVaultConfigurationStorage

/// Two vaults' auto-backup configurations, and which of them is open, as `OpenVaultBackupSettings` keeps them.
@MainActor
final class TwoVaultConfigurationStorage: AutoBackupConfigurationStorage {
    /// Each vault's configuration, as last saved.
    private(set) var saved: [AutoBackupConfiguration]
    /// The vault that's open, `0` or `1`, or `nil` when the app is locked.
    private(set) var openVault: Int? = 0
    private(set) var vaultToken = 0
    /// Whether the vaults are the plain store's, device-wide.
    let isDeviceWide: Bool

    init(
        first: AutoBackupConfiguration = .init(),
        second: AutoBackupConfiguration = .init(),
        isDeviceWide: Bool = false,
    ) {
        saved = [first, second]
        self.isDeviceWide = isDeviceWide
    }

    /// Opens the other vault, or locks when `vault` is `nil`, as the store session switching would.
    func open(_ vault: Int?) {
        openVault = vault
        vaultToken += 1
    }

    func autoBackupConfiguration() -> AutoBackupConfiguration? {
        openVault.map { saved[$0] }
    }

    func isOpen(_ token: Int) async -> Bool {
        token == vaultToken && openVault != nil
    }

    func saveAutoBackupConfiguration(_ configuration: AutoBackupConfiguration, for token: Int) async throws {
        guard token == vaultToken, let openVault else { throw VaultStoreSessionError.locked }
        saved[openVault] = configuration
    }
}

extension AutoBackupConfiguration {
    /// A plain store's configuration saved before auto-backup recorded its files, backing up to the stub provider
    /// `test`.
    static var fromBeforeFilesWereRecorded: AutoBackupConfiguration {
        var configuration = AutoBackupConfiguration.backingUp(providerConfig: "folder")
        configuration.backupFilenamesAreComplete = false
        return configuration
    }

    /// The default configuration, having written `backupFilenames`.
    static func written(_ backupFilenames: [String]) -> AutoBackupConfiguration {
        var configuration = AutoBackupConfiguration()
        configuration.backupFilenames = backupFilenames
        return configuration
    }

    /// Backing up to the stub provider `test`, whose configuration reads as `providerConfig`.
    static func backingUp(
        providerConfig: String,
        retention: AutoBackupRetention = .forever,
        isEnabled: Bool = true,
    ) -> AutoBackupConfiguration {
        AutoBackupConfiguration(
            isEnabled: isEnabled,
            retentionDays: retention,
            providerID: "test",
            providerConfigs: ["test": Data(providerConfig.utf8)],
            lastBackupHash: nil,
            lastBackupDate: nil,
        )
    }
}
