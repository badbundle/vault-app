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
    private let defaults: Defaults
    private let providers: [any BackupStorageProvider]

    private var debounceTask: Task<Void, Never>?
    private var restoreTask: Task<Void, Never>?
    /// The most recently queued backup; the next one waits on it. See `enqueueBackup`.
    private var backupChain: Task<Void, Never>?

    private static let configKey = Key<AutoBackupConfiguration>(VaultIdentifiers.AutoBackup.configuration)
    private static let debounceSeconds: UInt64 = 5

    // MARK: - Init

    public init(
        dataModel: VaultDataModel,
        backupEventLogger: any BackupEventLogger,
        clock: any EpochClock,
        defaults: Defaults,
        providers: [any BackupStorageProvider],
    ) {
        self.dataModel = dataModel
        self.backupEventLogger = backupEventLogger
        self.clock = clock
        self.defaults = defaults
        self.providers = providers
        configuration = defaults.get(for: Self.configKey) ?? AutoBackupConfiguration()

        restoreTask = Task { [weak self] in
            guard let self else { return }
            await restoreProviderConfigurations()
            updateStatus()
        }
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

    public func cleanupOldBackups() async {
        guard configuration.retentionDays.shouldCleanup else { return }
        guard let provider = selectedProvider else { return }
        guard await provider.isConfigured else { return }

        setStatus(.cleaningUp)

        do {
            let backups = try await provider.listBackups()
            let cutoffDate = Calendar.current.date(
                byAdding: .day,
                value: -configuration.retentionDays.rawValue,
                to: clock.currentDate,
            ) ?? clock.currentDate

            for backup in backups where backup.createdDate < cutoffDate {
                try await provider.delete(filename: backup.filename)
            }

            updateStatus()
        } catch {
            setStatus(.error(.cleanupFailed(reason: error.localizedDescription)))
        }
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
        guard let provider = selectedProvider else {
            setStatus(.error(.noProviderSelected))
            return
        }

        guard await provider.isConfigured else {
            setStatus(.error(.providerNotConfigured))
            return
        }

        guard await provider.isAvailable else {
            setStatus(.error(.providerUnavailable(reason: "Provider is not available")))
            return
        }

        guard case let .fetched(backupPassword) = dataModel.backupPassword else {
            setStatus(.error(.backupPasswordNotSet))
            return
        }

        let run = AutoBackupRun(trigger: trigger, startedAt: clock.currentDate)
        setStatus(.backingUp(run))

        do {
            // Export on the main actor; it is an in-memory read of the current vault.
            let payload = try await dataModel.makeExport(userDescription: "Auto-backup")

            // Generate PDF
            let pdfData = try await renderBackupPDF(payload: payload, backupPassword: backupPassword, run: run)

            // Create filename with timestamp
            let timestamp = VaultDateFormatter(timezone: .current).formatForFileName(date: clock.currentDate)
            let filename = "vault-auto-backup-\(timestamp).pdf"

            // Write to provider
            setStatus(.backingUp(run.with(progress: .init(phase: .saving))))
            try await provider.write(data: pdfData, filename: filename)

            // Update configuration with last backup info
            if let hash = dataModel.currentPayloadHash {
                configuration.lastBackupHash = hash.value.base64EncodedString()
            }
            configuration.lastBackupDate = clock.currentDate
            await saveConfiguration()

            // Log the event
            if let hash = dataModel.currentPayloadHash {
                backupEventLogger.exportedToAutoBackup(
                    date: clock.currentDate,
                    hash: hash,
                    providerID: provider.id,
                )
            }

            setStatus(.completed(clock.currentDate))

            // Clean up old backups
            await cleanupOldBackups()

        } catch let error as AutoBackupError {
            setStatus(.error(error))
        } catch {
            setStatus(.error(.unknown(reason: error.localizedDescription)))
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
    ) async throws -> Data {
        let (progress, continuation) = AsyncStream.makeStream(
            of: AutoBackupProgress.self,
            bufferingPolicy: .bufferingNewest(1),
        )
        async let pdfData = encryptAndRender(payload: payload, backupPassword: backupPassword, progress: continuation)
        for await update in progress {
            setStatus(.backingUp(run.with(progress: update)))
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

    private func setStatus(_ newStatus: AutoBackupStatus) {
        status = newStatus
        statusSubject.send(newStatus)
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
        // Save provider-specific configs
        for provider in providers {
            if let configData = await provider.configurationData {
                configuration.providerConfigs[provider.id] = configData
            }
        }

        try? defaults.set(configuration, for: Self.configKey)
        configurationSubject.send(configuration)
    }

    private func restoreProviderConfigurations() async {
        for provider in providers {
            if let configData = configuration.providerConfigs[provider.id] {
                try? await provider.restoreConfiguration(from: configData)
            }
        }
    }
}
