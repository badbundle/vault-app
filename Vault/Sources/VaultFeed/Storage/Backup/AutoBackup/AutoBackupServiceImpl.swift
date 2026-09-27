import Combine
import CryptoEngine
import Foundation
import FoundationExtensions
import PDFKit
import VaultBackup
import VaultCore
import VaultExport
import VaultKeygen

/// Default implementation of AutoBackupService.
///
/// **Each vault's own backups.** The configuration is the open vault's (`AutoBackupConfigurationStorage`), and follows
/// it when it changes (`vaultDidChange()`). A backup of one vault never writes into or updates another's, or shows in
/// it:
///
/// - The previous vault's destination is cleared as soon as the vault changes, and the next vault's isn't set up until
///   anything underway for the previous one has finished or stopped. A backup stops, without writing anything, if the
///   vault changes while it's underway, and records nothing once it has.
/// - It never replaces a file that's there already (`BackupStorageProvider.write(data:filename:)`); it picks another
///   name instead.
/// - Cleaning up only deletes the files this vault's auto-backup wrote (`AutoBackupConfiguration.backupFilenames`),
///   never another vault's, one written before they were recorded, or one the user put there (MANIFESTO C10).
@MainActor
public final class AutoBackupServiceImpl: AutoBackupService {
    // MARK: - Public Properties

    public private(set) var status: AutoBackupStatus = .disabled
    public private(set) var configuration: AutoBackupConfiguration

    public var availableProviders: [any BackupStorageProvider] {
        providers
    }

    public var selectedProvider: (any BackupStorageProvider)? {
        guard let providerID = configuration.providerID else { return nil }
        return providers.first { $0.id == providerID }
    }

    // MARK: - Publishers

    private let statusSubject = PassthroughSubject<AutoBackupStatus, Never>()
    private let configurationSubject = PassthroughSubject<AutoBackupConfiguration, Never>()

    public var statusPublisher: AnyPublisher<AutoBackupStatus, Never> {
        statusSubject.eraseToAnyPublisher()
    }

    public var configurationPublisher: AnyPublisher<AutoBackupConfiguration, Never> {
        configurationSubject.eraseToAnyPublisher()
    }

    // MARK: - Dependencies

    private let dataModel: VaultDataModel
    private let backupEventLogger: any BackupEventLogger
    private let clock: any EpochClock
    private let configurationStorage: any AutoBackupConfigurationStorage
    private let providers: [any BackupStorageProvider]
    /// Goes up whenever the open vault changes. A backup, or a clean-up, that started for one vault stops before it
    /// changes anything once this has moved on.
    private var vaultGeneration = 0
    /// Identifies the vault `configuration` was read from (`AutoBackupConfigurationStorage.vaultToken`).
    private var vaultToken: Int
    /// The `vaultGeneration` the providers are set up for. Until it's the current one, they hold no destination of
    /// the open vault's: nothing is backed up, and their configuration isn't saved into the vault's.
    private var providersGeneration = 0

    private var debounceTask: Task<Void, Never>?
    private var restoreTask: Task<Void, Never>?
    /// The most recently queued backup; the next one waits on it. See `enqueueBackup`.
    private var backupChain: Task<Void, Never>?

    private static let debounceSeconds: UInt64 = 5
    /// How many names a backup tries, adding `-2`, `-3` and so on, when a file with its name is there already.
    private static let filenameAttempts = 5

    // MARK: - Init

    /// - Parameter configurationStorage: Where the open vault's configuration is.
    public init(
        dataModel: VaultDataModel,
        backupEventLogger: any BackupEventLogger,
        clock: any EpochClock,
        configurationStorage: any AutoBackupConfigurationStorage,
        providers: [any BackupStorageProvider],
    ) {
        self.dataModel = dataModel
        self.backupEventLogger = backupEventLogger
        self.clock = clock
        self.configurationStorage = configurationStorage
        self.providers = providers
        vaultToken = configurationStorage.vaultToken
        configuration = configurationStorage.autoBackupConfiguration() ?? AutoBackupConfiguration()

        let providerConfigs = configuration.providerConfigs
        restoreTask = Task { [weak self] in
            guard let self else { return }
            await restoreProviderConfigurations(providerConfigs)
            guard vaultGeneration == 0 else { return }
            updateStatus()
            await seedBackupFilenamesIfNeeded()
        }
    }

    /// Keeps the configuration in `UserDefaults`, device-wide.
    public convenience init(
        dataModel: VaultDataModel,
        backupEventLogger: any BackupEventLogger,
        clock: any EpochClock,
        defaults: Defaults,
        providers: [any BackupStorageProvider],
    ) {
        self.init(
            dataModel: dataModel,
            backupEventLogger: backupEventLogger,
            clock: clock,
            configurationStorage: defaults,
            providers: providers,
        )
    }

    deinit {
        restoreTask?.cancel()
        debounceTask?.cancel()
    }

    // MARK: - Configuration

    public func setEnabled(_ enabled: Bool) async {
        configuration.isEnabled = enabled
        await saveConfiguration()
        updateStatus()

        if enabled {
            await triggerBackupIfNeeded()
        }
    }

    public func forgetConfiguration() async {
        // Like a change of vault, with none to follow: anything underway stops, and nothing is backed up, or saved,
        // until
        // the next vault opens (`vaultDidChange()`).
        vaultGeneration += 1
        let generation = vaultGeneration
        debounceTask?.cancel()
        debounceTask = nil
        configuration = AutoBackupConfiguration()
        updateStatus()
        for provider in providers {
            guard generation == vaultGeneration else { return }
            await provider.clearConfiguration()
        }
        guard generation == vaultGeneration else { return }
        configurationSubject.send(configuration)
    }

    public func selectProvider(id: String) async {
        configuration.providerID = id
        await saveConfiguration()
        // Don't call updateStatus() here - selecting a provider shouldn't reset error states
    }

    public func setRetention(_ retention: AutoBackupRetention) async {
        configuration.retentionDays = retention
        await saveConfiguration()

        // Run cleanup with new retention settings
        await cleanupOldBackups()
    }

    // MARK: - Backup Operations

    public func triggerBackupIfNeeded() async {
        guard configuration.isEnabled else { return }

        // The checks run once any in-flight backup has finished, so a change made during that backup
        // is still picked up rather than compared against a stale hash.
        await enqueueBackup { [weak self] in
            guard let self else { return }
            guard let provider = selectedProvider else { return }
            guard await provider.isConfigured else { return }
            guard hasChangesSinceLastBackup else { return }
            await performBackup(trigger: .automatic)
        }
    }

    public func forceBackup() async {
        await enqueueBackup { [weak self] in
            await self?.performBackup(trigger: .manual)
        }
    }

    public func saveProviderConfiguration() async {
        await saveConfiguration()
    }

    /// Deletes this vault's backups that are older than its retention, and only those: never a file its
    /// auto-backup didn't write.
    ///
    /// Then it forgets the files it deleted, and any the user has, whatever the retention, so the list doesn't grow
    /// for files that are gone. A file that isn't listed is only forgotten once the provider says it's gone
    /// (`BackupStorageProvider.containsBackup(filename:)`): one only in the cloud for now, or missed by one listing, is
    /// still there, and still to clean up.
    public func cleanupOldBackups() async {
        await seedBackupFilenamesIfNeeded()
        let generation = vaultGeneration
        let retention = configuration.retentionDays
        let own = Set(configuration.backupFilenames)
        guard !own.isEmpty else { return }
        guard let provider = selectedProvider else { return }
        guard await provider.isConfigured, await isStillForTheOpenVault(generation) else { return }

        if retention.shouldCleanup {
            setStatus(.cleaningUp)
        }

        do {
            let backups = try await provider.listBackups()
            var forgotten = Set<String>()
            if retention.shouldCleanup {
                let cutoffDate = Calendar.current.date(
                    byAdding: .day,
                    value: -retention.rawValue,
                    to: clock.currentDate,
                ) ?? clock.currentDate
                for backup in backups where own.contains(backup.filename) && backup.createdDate < cutoffDate {
                    guard generation == vaultGeneration else { return }
                    try await provider.delete(filename: backup.filename)
                    forgotten.insert(backup.filename)
                }
            }
            let listed = Set(backups.map(\.filename))
            for filename in own.subtracting(listed).sorted() {
                guard generation == vaultGeneration else { return }
                // If it can't say, the file's taken to be there.
                let isThere = (try? await provider.containsBackup(filename: filename)) ?? true
                if !isThere {
                    forgotten.insert(filename)
                }
            }
            guard generation == vaultGeneration else { return }
            if !forgotten.isEmpty {
                configuration.backupFilenames.removeAll { forgotten.contains($0) }
                await saveConfiguration()
            }

            if retention.shouldCleanup {
                updateStatus()
            }
        } catch {
            guard generation == vaultGeneration, retention.shouldCleanup else { return }
            setStatus(.error(.cleanupFailed(reason: error.localizedDescription)))
        }
    }

    /// Seeds the plain store's list of backup files, once, from its folder, if it was saved before the files were
    /// recorded: every auto-backup file there, which is what cleaning up deleted before. So existing backups are
    /// still cleaned up once they're past the retention.
    ///
    /// Never for an encrypted vault's: the folder could hold another vault's backups (MANIFESTO C10).
    private func seedBackupFilenamesIfNeeded() async {
        guard !configuration.backupFilenamesAreComplete else { return }
        let generation = vaultGeneration
        guard let provider = selectedProvider else { return }
        guard await provider.isConfigured, await isStillForTheOpenVault(generation) else { return }
        guard configurationStorage.isDeviceWide else { return }
        guard let backups = try? await provider.listBackups(), generation == vaultGeneration else { return }
        let recorded = Set(configuration.backupFilenames)
        configuration.backupFilenames += backups.map(\.filename).filter { !recorded.contains($0) }
        configuration.backupFilenamesAreComplete = true
        await saveConfiguration()
    }

    // MARK: - Vault

    public func vaultDidChange() async {
        vaultGeneration += 1
        let generation = vaultGeneration
        debounceTask?.cancel()
        // The configuration and status are the open vault's at once, and the previous vault's destination is cleared,
        // so a backup of it that's still underway can't write there any more.
        vaultToken = configurationStorage.vaultToken
        configuration = configurationStorage.autoBackupConfiguration() ?? AutoBackupConfiguration()
        updateStatus()
        await restoreTask?.value
        for provider in providers {
            guard generation == vaultGeneration else { return }
            await provider.clearConfiguration()
        }
        guard generation == vaultGeneration else { return }
        configurationSubject.send(configuration)
        // Anything underway for the previous vault finishes, or stops, before this vault's destination is set up: it
        // can't then write into it.
        await backupChain?.value
        guard generation == vaultGeneration else { return }
        await restoreProviderConfigurations(configuration.providerConfigs)
        guard generation == vaultGeneration else { return }
        providersGeneration = generation
        // Again, now the destination is set up, so what's shown of it is this vault's.
        configurationSubject.send(configuration)
        updateStatus()
        await seedBackupFilenamesIfNeeded()
    }

    // MARK: - Monitoring

    /// Called by external code when data changes are detected.
    /// This should be called after any vault mutation.
    public func notifyDataChanged() {
        guard configuration.isEnabled else { return }

        debounceTask?.cancel()
        debounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.debounceSeconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await triggerBackupIfNeeded()
        }
    }

    // MARK: - Private

    private var hasChangesSinceLastBackup: Bool {
        guard let currentHash = dataModel.currentPayloadHash?.value.base64EncodedString(),
              let lastHash = configuration.lastBackupHash
        else { return true }
        return currentHash != lastHash
    }

    /// Backups run one at a time, in the order requested. `performBackup` suspends several times, so
    /// without this a debounced auto-backup could interleave with a manual one: two files written and
    /// the two progress sequences fighting over `status`.
    private func enqueueBackup(_ operation: @escaping @MainActor () async -> Void) async {
        let previous = backupChain
        let task = Task { @MainActor in
            await previous?.value
            await operation()
        }
        backupChain = task
        await task.value
        // Don't hold on to a finished task; a later caller would only wait on it needlessly.
        if backupChain == task {
            backupChain = nil
        }
    }

    private func performBackup(trigger: AutoBackupRun.Trigger) async {
        let generation = vaultGeneration
        // The vault being backed up, which the backup is logged into, and no other.
        let eventVaultToken = backupEventLogger.vaultToken
        guard let provider = selectedProvider else {
            setStatus(for: generation, .error(.noProviderSelected))
            return
        }

        guard await provider.isConfigured else {
            setStatus(for: generation, .error(.providerNotConfigured))
            return
        }

        guard await provider.isAvailable else {
            setStatus(for: generation, .error(.providerUnavailable(reason: "Provider is not available")))
            return
        }

        guard case let .fetched(backupPassword) = dataModel.backupPassword else {
            setStatus(for: generation, .error(.backupPasswordNotSet))
            return
        }

        guard await isStillForTheOpenVault(generation) else { return }
        let run = AutoBackupRun(trigger: trigger, startedAt: clock.currentDate)
        setStatus(for: generation, .backingUp(run))

        do {
            // Export on the main actor; it is an in-memory read of the current vault.
            let payload = try await dataModel.makeExport(userDescription: "Auto-backup")

            // Generate PDF
            let pdfData = try await renderBackupPDF(
                payload: payload,
                backupPassword: backupPassword,
                run: run,
                generation: generation,
            )

            // The vault changed while it was exported or rendered: this backup may be of another vault, which
            // mustn't go into this vault's destination.
            guard await isStillForTheOpenVault(generation) else { return }
            let payloadHash = dataModel.currentPayloadHash

            // Write to provider
            setStatus(for: generation, .backingUp(run.with(progress: .init(phase: .saving))))
            let filename = try await writeNewFile(pdfData, to: provider)
            // The vault changed while it was written: the file is the previous vault's, and nothing about it goes into
            // the configuration of the vault that's open now.
            guard generation == vaultGeneration else { return }

            // Update configuration with last backup info
            if let payloadHash {
                configuration.lastBackupHash = payloadHash.value.base64EncodedString()
            }
            configuration.lastBackupDate = clock.currentDate
            configuration.backupFilenames.append(filename)
            await saveConfiguration()

            // Log the event, into this vault's settings only. Nothing else runs between the check and the log.
            guard await isStillForTheOpenVault(generation) else { return }
            if let payloadHash {
                backupEventLogger.exportedToAutoBackup(
                    backupDate: clock.currentDate,
                    hash: payloadHash,
                    providerID: provider.id,
                    vaultToken: eventVaultToken,
                )
            }

            setStatus(for: generation, .completed(clock.currentDate))

            // Clean up old backups
            await cleanupOldBackups()

        } catch let error as AutoBackupError {
            setStatus(for: generation, .error(error))
        } catch {
            setStatus(for: generation, .error(.unknown(reason: error.localizedDescription)))
        }
    }

    /// Encrypts and renders the backup off the main actor, mirroring each progress update into `status`.
    ///
    /// Progress goes through a stream rather than ad-hoc main-actor hops so that updates land in order and
    /// every one of them is applied before this returns; a late `.backingUp` must never overwrite `.completed`.
    private func renderBackupPDF(
        payload: VaultApplicationPayload,
        backupPassword: DerivedEncryptionKey,
        run: AutoBackupRun,
        generation: Int,
    ) async throws -> Data {
        let (progress, continuation) = AsyncStream.makeStream(
            of: AutoBackupProgress.self,
            bufferingPolicy: .bufferingNewest(1),
        )
        async let pdfData = encryptAndRender(payload: payload, backupPassword: backupPassword, progress: continuation)
        for await update in progress {
            setStatus(for: generation, .backingUp(run.with(progress: update)))
        }
        return try await pdfData
    }

    /// Runs off the main actor: rendering every QR code twice is slow and would otherwise freeze the UI.
    private nonisolated func encryptAndRender(
        payload: VaultApplicationPayload,
        backupPassword: DerivedEncryptionKey,
        progress: AsyncStream<AutoBackupProgress>.Continuation,
    ) async throws -> Data {
        defer { progress.finish() }

        // Encrypt the payload
        progress.yield(.init(phase: .encrypting))
        let encoder = EncryptedVaultEncoder(clock: clock, backupPassword: backupPassword)
        let encryptedVault = try encoder.encryptAndEncode(payload: payload)

        // Create export payload
        let exportPayload = VaultExportPayload(
            encryptedVault: encryptedVault,
            userDescription: "Automatic backup created by Vault",
            created: clock.currentDate,
        )

        // Generate PDF
        let pdfGenerator = VaultBackupPDFGenerator(
            size: A4DocumentSize(),
            documentTitle: "Auto-Backup",
            applicationName: "Vault",
            authorName: "Vault",
        )

        progress.yield(.init(phase: .rendering))
        let pdfDocument = try pdfGenerator.makePDF(payload: exportPayload) { fraction in
            progress.yield(.init(phase: .rendering, phaseFraction: fraction))
        }

        guard let pdfData = pdfDocument.dataRepresentation() else {
            throw AutoBackupError.pdfGenerationFailed(reason: "Failed to get PDF data")
        }

        return pdfData
    }

    /// Whether work that started for the vault open at `generation` can still change anything: neither this service
    /// nor the store session has moved on to another vault since.
    private func isStillForTheOpenVault(_ generation: Int) async -> Bool {
        guard generation == vaultGeneration, providersGeneration == generation else { return false }
        let isOpen = await configurationStorage.isOpen(vaultToken)
        return isOpen && generation == vaultGeneration
    }

    /// Writes the backup as a new file, named for now. If a file with that name is there already, which could be
    /// another vault's, it tries `-2`, `-3` and so on rather than replace it.
    ///
    /// - Returns: The name it was written with.
    private func writeNewFile(_ data: Data, to provider: any BackupStorageProvider) async throws -> String {
        let timestamp = VaultDateFormatter(timezone: .current).formatForFileName(date: clock.currentDate)
        for attempt in 1 ... Self.filenameAttempts {
            let suffix = attempt == 1 ? "" : "-\(attempt)"
            let filename = "vault-auto-backup-\(timestamp)\(suffix).pdf"
            do {
                try await provider.write(data: data, filename: filename)
                return filename
            } catch AutoBackupError.backupFileExists {
                continue
            }
        }
        throw AutoBackupError.backupFileExists
    }

    private func setStatus(_ newStatus: AutoBackupStatus) {
        status = newStatus
        statusSubject.send(newStatus)
    }

    /// Sets the status of work that started for the vault open at `generation`, unless another vault has opened
    /// since: it mustn't show there.
    private func setStatus(for generation: Int, _ newStatus: AutoBackupStatus) {
        guard generation == vaultGeneration else { return }
        setStatus(newStatus)
    }

    private func updateStatus() {
        if !configuration.isEnabled {
            setStatus(.disabled)
        } else if let lastBackupDate = configuration.lastBackupDate {
            setStatus(.completed(lastBackupDate))
        } else {
            setStatus(.idle)
        }
    }

    private func saveConfiguration() async {
        let generation = vaultGeneration
        // Save provider-specific configs, but only while they're set up for this vault: while the vault is changing,
        // they hold none of its own.
        if providersGeneration == generation {
            for provider in providers {
                let configData = await provider.configurationData
                guard generation == vaultGeneration else { return }
                if let configData {
                    configuration.providerConfigs[provider.id] = configData
                }
            }
        }

        // Dropped if the vault it belongs to isn't open any more: it's that vault's, not the next one's.
        guard generation == vaultGeneration else { return }
        try? await configurationStorage.saveAutoBackupConfiguration(configuration, for: vaultToken)
        configurationSubject.send(configuration)
    }

    private func restoreProviderConfigurations(_ providerConfigs: [String: Data]) async {
        for provider in providers {
            if let configData = providerConfigs[provider.id] {
                try? await provider.restoreConfiguration(from: configData)
            }
        }
    }
}
