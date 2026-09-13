import Foundation
import SwiftUI
import UniformTypeIdentifiers
import VaultFeed

/// View for configuring and monitoring auto-backup settings.
@MainActor
struct AutoBackupSettingsView: View {
    @Environment(VaultInjector.self) var injector
    let autoBackupService: any AutoBackupService

    @State private var isShowingFolderPicker = false
    @State private var selectedProviderID: String?
    @State private var providerConfigStates: [String: Bool] = [:]
    @State private var providerConfigSummaries: [String: String] = [:]

    // Local state to observe changes from publishers
    @State private var status: AutoBackupStatus = .disabled
    @State private var configuration: AutoBackupConfiguration = .init()

    var body: some View {
        Section {
            enabledToggle

            if configuration.isEnabled {
                destinationRow

                if selectedProviderIsConfigured {
                    retentionPicker
                }

                if case let .error(error) = status {
                    errorRow(error)
                }

                if selectedProviderIsConfigured {
                    backupNowButton
                }
            }
        } footer: {
            Text(footerText)
        }
        .sheet(isPresented: $isShowingFolderPicker) {
            FolderPickerView { url in
                configureSelectedProvider(with: url)
            }
        }
        .task {
            // Initialize with current values
            status = autoBackupService.status
            configuration = autoBackupService.configuration
            await loadProviderConfigStates()
        }
        .onReceive(autoBackupService.statusPublisher) { newStatus in
            status = newStatus
        }
        .onReceive(autoBackupService.configurationPublisher) { newConfiguration in
            configuration = newConfiguration
            // Refresh provider states when configuration changes
            Task {
                await loadProviderConfigStates()
            }
        }
    }

    // MARK: - Rows

    private var enabledToggle: some View {
        Toggle(isOn: Binding(
            get: { configuration.isEnabled },
            set: { enabled in
                Task {
                    await autoBackupService.setEnabled(enabled)
                }
            },
        )) {
            FormRow(image: Image(systemName: statusIconName), color: statusColor) {
                Text("Auto-Backup")
            }
        }
    }

    private var destinationRow: some View {
        Button {
            if let provider = autoBackupService.availableProviders.first {
                Task {
                    await autoBackupService.selectProvider(id: provider.id)
                }
                selectedProviderID = provider.id
                isShowingFolderPicker = true
            }
        } label: {
            LabeledContent {
                Text(selectedProviderSummary ?? "Choose a folder")
            } label: {
                FormRow(image: Image(systemName: "folder.fill"), color: .green) {
                    Text("Destination")
                }
            }
        }
    }

    private var retentionPicker: some View {
        Picker(selection: Binding(
            get: { configuration.retentionDays },
            set: { retention in
                Task {
                    await autoBackupService.setRetention(retention)
                }
            },
        )) {
            ForEach(AutoBackupRetention.allCases, id: \.self) { retention in
                Text(retention.localizedTitle).tag(retention)
            }
        } label: {
            FormRow(image: Image(systemName: "clock.arrow.circlepath"), color: .blue) {
                Text("Keep Backups For")
            }
        }
    }

    private func errorRow(_ error: AutoBackupError) -> some View {
        FormRow(
            image: Image(systemName: "exclamationmark.triangle.fill"),
            color: .orange,
            alignment: .firstTextBaseline,
        ) {
            TextAndSubtitle(
                title: error.errorDescription ?? "An error occurred",
                subtitle: error.recoverySuggestion,
            )
        }
    }

    private var backupNowButton: some View {
        AsyncButton {
            await autoBackupService.forceBackup()
        } label: {
            FormRow(image: Image(systemName: "arrow.clockwise.icloud"), color: .accentColor) {
                Text("Backup Now")
            }
        } loading: {
            FormRow(image: Image(systemName: "arrow.clockwise.icloud"), color: .accentColor) {
                ProgressView()
            }
        }
        .disabled(isBackingUp)
    }

    // MARK: - Helpers

    /// When auto-backup is off the footer explains what the feature does; once it is on, the footer
    /// carries the live status so the state is visible without a separate status row.
    private var footerText: String {
        guard configuration.isEnabled else {
            return "Enable to automatically back up your vault to cloud storage whenever changes are made."
        }
        return statusDescription
    }

    private var statusColor: Color {
        switch status {
        case .disabled:
            .gray
        case .idle, .completed:
            .green
        case .backingUp, .cleaningUp:
            .accentColor
        case .error:
            .orange
        }
    }

    private var statusIconName: String {
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

    private var statusDescription: String {
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

    private var isBackingUp: Bool {
        if case .backingUp = status {
            return true
        }
        if case .cleaningUp = status {
            return true
        }
        return false
    }

    private var selectedProviderIsConfigured: Bool {
        guard let providerID = configuration.providerID else { return false }
        return providerConfigStates[providerID] ?? false
    }

    private var selectedProviderSummary: String? {
        guard let providerID = configuration.providerID else { return nil }
        return providerConfigSummaries[providerID]
    }

    private func loadProviderConfigStates() async {
        for provider in autoBackupService.availableProviders {
            providerConfigStates[provider.id] = await provider.isConfigured
            if let summary = await provider.configurationSummary {
                providerConfigSummaries[provider.id] = summary
            }
        }
    }

    private func configureSelectedProvider(with url: URL) {
        guard let providerID = selectedProviderID,
              let provider = autoBackupService.availableProviders.first(where: { $0.id == providerID })
        else { return }

        Task {
            do {
                try await provider.configure(with: url)
                // Save the configuration to persistent storage
                await autoBackupService.saveProviderConfiguration()
                await loadProviderConfigStates()
                // Trigger a backup now that it's configured
                await autoBackupService.triggerBackupIfNeeded()
            } catch {
                // Configuration failed - the provider will remain unconfigured
            }
        }
    }
}

// MARK: - Folder Picker

private struct FolderPickerView: UIViewControllerRepresentable {
    let onFolderSelected: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_: UIDocumentPickerViewController, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFolderSelected: onFolderSelected)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFolderSelected: (URL) -> Void

        init(onFolderSelected: @escaping (URL) -> Void) {
            self.onFolderSelected = onFolderSelected
        }

        func documentPicker(_: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onFolderSelected(url)
        }
    }
}
