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
    /// Briefly true after a backup finishes, so the screen can confirm it rather than silently
    /// re-enabling the button. Driven by the transition into `.completed`, not by the sticky
    /// `.completed` status itself, which is what the service rests on between backups.
    public internal(set) var showsBackupCompleteNotice = false

    /// False until the providers have reported whether they're configured, so the screen doesn't flash
    /// "choose a folder" for a destination that is already set up.
    public private(set) var hasLoadedProviderStates: Bool

    private let service: any AutoBackupService
    private let providerStatesWereSeeded: Bool
    private let completionNoticeDuration: Duration
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var completionNoticeTask: Task<Void, Never>?
    /// Set when a backup starts and cleared when it completes, so only a real backup earns the notice.
    @ObservationIgnored private var isAwaitingBackupCompletion = false

    public init(
        service: any AutoBackupService,
        initialProviderStates: [ProviderDisplayState] = [],
        completionNoticeDuration: Duration = .seconds(2),
    ) {
        self.service = service
        providerStatesWereSeeded = !initialProviderStates.isEmpty
        self.completionNoticeDuration = completionNoticeDuration
        // Seed synchronously: the service's publishers do not replay, so
        // waiting for an emission would leave the screen stuck on defaults.
        status = service.status
        configuration = service.configuration
        providerStates = initialProviderStates
        hasLoadedProviderStates = !initialProviderStates.isEmpty

        service.statusPublisher
            .sink { [weak self] newStatus in
                self?.apply(newStatus)
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
        hasLoadedProviderStates = true
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

    /// The in-flight backup, or nil when none is running.
    public var currentRun: AutoBackupRun? {
        if case let .backingUp(run) = status {
            run
        } else {
            nil
        }
    }

    /// When the last successful auto-backup finished.
    public var lastBackupDate: Date? {
        if case let .completed(date) = status {
            date
        } else {
            configuration.lastBackupDate
        }
    }

    /// The folder backups are saved to, for use in a sentence.
    public var destinationName: String {
        activeProvider?.folderSummary.map { "“\($0)”" } ?? "your backup folder"
    }

    /// When auto-backup runs and how long it keeps backups, in a sentence.
    public var scheduleSummary: String {
        let retention = if configuration.retentionDays.shouldCleanup {
            "Backups older than \(configuration.retentionDays.localizedTitle) are deleted."
        } else {
            "Old backups are never deleted."
        }
        return "A new encrypted backup is saved a few seconds after your vault changes. \(retention)"
    }

    private func apply(_ newStatus: AutoBackupStatus) {
        status = newStatus
        switch newStatus {
        case .backingUp:
            isAwaitingBackupCompletion = true
            hideCompletionNotice()
        case .completed where isAwaitingBackupCompletion:
            isAwaitingBackupCompletion = false
            showCompletionNotice()
        case .error, .disabled, .idle:
            isAwaitingBackupCompletion = false
            hideCompletionNotice()
        case .completed, .cleaningUp:
            // A retention change alone cleans up and re-emits `.completed`; that is not a backup.
            break
        }
    }

    private func showCompletionNotice() {
        completionNoticeTask?.cancel()
        showsBackupCompleteNotice = true
        completionNoticeTask = Task { [weak self, completionNoticeDuration] in
            try? await Task.sleep(for: completionNoticeDuration)
            guard !Task.isCancelled else { return }
            self?.showsBackupCompleteNotice = false
        }
    }

    private func hideCompletionNotice() {
        completionNoticeTask?.cancel()
        completionNoticeTask = nil
        showsBackupCompleteNotice = false
    }

    /// The screen's headline: whether auto-backup is on and what it's doing right now.
    public struct StatusHeader: Equatable, Sendable {
        public enum Tone: Equatable, Sendable {
            /// Auto-backup is off.
            case off
            /// Auto-backup is on and has nothing to report.
            case healthy
            /// A backup or clean-up is running.
            case working
            /// Auto-backup needs attention before it can back up.
            case attention
        }

        public var title: String
        public var subtitle: String
        public var systemImage: String
        public var tone: Tone
    }

    public var statusHeader: StatusHeader {
        guard configuration.isEnabled else {
            return StatusHeader(
                title: "Auto-Backup Is Off",
                subtitle: "Turn it on to save an encrypted backup to a folder you choose whenever your vault changes.",
                systemImage: "icloud.slash",
                tone: .off,
            )
        }

        switch status {
        case .backingUp:
            return StatusHeader(
                title: "Backing Up",
                subtitle: "Saving an encrypted copy of your vault to \(destinationName).",
                systemImage: "arrow.clockwise.icloud",
                tone: .working,
            )
        case let .error(error):
            // Some descriptions come from the system and already end in a full stop.
            let description = error.errorDescription.map { $0.hasSuffix(".") ? String($0.dropLast()) : $0 }
            let explanation = [description, error.recoverySuggestion].compactMap(\.self)
            return StatusHeader(
                title: "Last Backup Failed",
                subtitle: explanation.isEmpty ? "Something went wrong." : explanation.joined(separator: ". "),
                systemImage: "exclamationmark.icloud",
                tone: .attention,
            )
        case .disabled, .idle, .completed, .cleaningUp:
            // Clean-up follows every backup and usually takes a moment, so it stays out of the headline
            // rather than flashing past; the activity section shows it instead.
            if hasLoadedProviderStates, !isDestinationConfigured {
                return StatusHeader(
                    title: "Choose a Folder",
                    subtitle: "Auto-backup is on, but it needs a folder to save backups to.",
                    systemImage: "exclamationmark.icloud",
                    tone: .attention,
                )
            }
            let subtitle = if let lastBackupDate {
                "Last backed up \(lastBackupDate.formatted(date: .abbreviated, time: .shortened))."
            } else {
                "Your vault is saved to \(destinationName) whenever it changes."
            }
            return StatusHeader(
                title: "Auto-Backup Is On",
                subtitle: subtitle,
                systemImage: "checkmark.icloud",
                tone: .healthy,
            )
        }
    }
}
