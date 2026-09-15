import Combine
import Foundation

@MainActor
@Observable
public final class AutoBackupViewModel {
    /// Snapshot of a storage provider's display information, decoupled from
    /// the async provider protocol so views and tests can render synchronously.
    public struct ProviderDisplayState: Equatable, Sendable, Identifiable {
        public let id: String
        public let displayName: String
        public let iconSystemName: String
        public var isConfigured: Bool
        public var folderSummary: String?

        public init(
            id: String,
            displayName: String,
            iconSystemName: String,
            isConfigured: Bool,
            folderSummary: String?,
        ) {
            self.id = id
            self.displayName = displayName
            self.iconSystemName = iconSystemName
            self.isConfigured = isConfigured
            self.folderSummary = folderSummary
        }
    }

    public private(set) var status: AutoBackupStatus
    public private(set) var configuration: AutoBackupConfiguration
    public private(set) var providerStates: [ProviderDisplayState]
    public internal(set) var configureError: AutoBackupError?

    private let service: any AutoBackupService
    private let providerStatesWereSeeded: Bool
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    public init(
        service: any AutoBackupService,
        initialProviderStates: [ProviderDisplayState] = [],
    ) {
        self.service = service
        providerStatesWereSeeded = !initialProviderStates.isEmpty
        // Seed synchronously: the service's publishers do not replay, so
        // waiting for an emission would leave the screen stuck on defaults.
        status = service.status
        configuration = service.configuration
        providerStates = initialProviderStates

        service.statusPublisher
            .sink { [weak self] newStatus in
                self?.status = newStatus
            }
            .store(in: &cancellables)

        service.configurationPublisher
            .sink { [weak self] newConfiguration in
                guard let self else { return }
                configuration = newConfiguration
                Task {
                    await self.refreshProviderStates()
                }
            }
            .store(in: &cancellables)
    }

    /// The provider the destination row acts on: the configured one if any,
    /// otherwise the first available. The single seam for future
    /// multi-provider selection.
    public var activeProvider: ProviderDisplayState? {
        if let providerID = configuration.providerID,
           let selected = providerStates.first(where: { $0.id == providerID })
        {
            return selected
        }
        return providerStates.first
    }

    public var isDestinationConfigured: Bool {
        activeProvider?.isConfigured ?? false
    }

    /// Hydrates provider states on first appearance. Seeded states (tests,
    /// previews) are authoritative and must not be clobbered by a refresh
    /// against a service that vends no providers.
    public func onAppear() async {
        guard !providerStatesWereSeeded else { return }
        await refreshProviderStates()
    }

    public func refreshProviderStates() async {
        var states = [ProviderDisplayState]()
        for provider in service.availableProviders {
            states.append(ProviderDisplayState(
                id: provider.id,
                displayName: provider.displayName,
                iconSystemName: provider.iconSystemName,
                isConfigured: await provider.isConfigured,
                folderSummary: await provider.configurationSummary,
            ))
        }
        providerStates = states
    }

    /// Marks the active provider as selected ahead of a folder pick and
    /// clears any stale configuration error so a repeated failure re-renders.
    public func beginDestinationSelection() async {
        configureError = nil
        guard let provider = activeProvider else { return }
        await service.selectProvider(id: provider.id)
    }

    public func configureDestination(url: URL) async {
        guard let providerID = activeProvider?.id,
              let provider = service.availableProviders.first(where: { $0.id == providerID })
        else { return }

        do {
            try await provider.configure(with: url)
            await service.saveProviderConfiguration()
            await refreshProviderStates()
            await service.triggerBackupIfNeeded()
        } catch let error as AutoBackupError {
            configureError = error
        } catch {
            configureError = .unknown(reason: error.localizedDescription)
        }
    }

    public func setEnabled(_ enabled: Bool) async {
        await service.setEnabled(enabled)
    }

    public func setRetention(_ retention: AutoBackupRetention) async {
        await service.setRetention(retention)
    }

    public func backupNow() async {
        await service.forceBackup()
    }

    // MARK: - Status Presentation

    public var isBackingUp: Bool {
        switch status {
        case .backingUp, .cleaningUp: true
        case .disabled, .idle, .error, .completed: false
        }
    }

    public var statusIconName: String {
        switch status {
        case .disabled:
            "icloud.slash"
        case .idle:
            "icloud"
        case .backingUp, .cleaningUp:
            "arrow.clockwise.icloud"
        case .completed:
            "checkmark.icloud"
        case .error:
            "exclamationmark.icloud"
        }
    }

    public var statusDescription: String {
        switch status {
        case .disabled:
            "Automatic backups are disabled"
        case .idle:
            "Ready to back up when changes occur"
        case .backingUp:
            "Backing up..."
        case .cleaningUp:
            "Cleaning up old backups..."
        case let .completed(date):
            "Last backup: \(date.formatted(date: .abbreviated, time: .shortened))"
        case .error:
            "Backup failed"
        }
    }

    /// When auto-backup is off the footer explains what the feature does; once it is on, the footer
    /// carries the live status so the state is visible without a separate status row.
    public var footerText: String {
        guard configuration.isEnabled else {
            return "Enable to automatically back up your vault to cloud storage whenever changes are made."
        }
        return statusDescription
    }
}
