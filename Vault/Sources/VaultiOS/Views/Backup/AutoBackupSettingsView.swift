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
        VStack(alignment: .leading, spacing: 16) {
            headerView

            if configuration.isEnabled {
                enabledContentView
            } else {
                disabledContentView
            }
        }
        .padding(16)
        .modifier(VaultCardModifier(configuration: .init(
            style: .secondary,
            border: borderColor,
            padding: .init(),
        )))
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

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 12) {
            Image(systemName: statusIconName)
                .font(.title2)
                .foregroundStyle(statusColor)
                .frame(width: 40, height: 40)
                .background(statusColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text("Auto-Backup")
                    .font(.headline.bold())
                    .foregroundStyle(.primary)

                Text(statusDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { configuration.isEnabled },
                set: { enabled in
                    Task {
                        await autoBackupService.setEnabled(enabled)
                    }
                },
            ))
            .labelsHidden()
        }
    }

    // MARK: - Enabled Content

    private var enabledContentView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            destinationRow

            if selectedProviderIsConfigured {
                retentionPickerView
            }

            if case let .error(error) = status {
                errorView(error)
            }

            if selectedProviderIsConfigured {
                backupNowButton
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
            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.green)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Destination")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let summary = selectedProviderSummary {
                        Text(summary)
                            .font(.body)
                            .foregroundStyle(.primary)
                    } else {
                        Text("Choose a folder")
                            .font(.body)
                            .foregroundStyle(Color.accentColor)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .tertiaryLabel))
            }
        }
        .buttonStyle(.plain)
    }

    private var retentionPickerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Keep backups for")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Retention", selection: Binding(
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
            }
            .pickerStyle(.segmented)
        }
    }

    private func errorView(_ error: AutoBackupError) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(error.errorDescription ?? "An error occurred")
                    .font(.callout)
                    .foregroundStyle(.primary)

                if let recovery = error.recoverySuggestion {
                    Text(recovery)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var backupNowButton: some View {
        AsyncButton(progressAlignment: .center) {
            await autoBackupService.forceBackup()
        } label: {
            Label("Backup Now", systemImage: "arrow.clockwise.icloud")
                .frame(maxWidth: .infinity)
        } loading: {
            ProgressView()
                .tint(.white)
        }
        .modifier(ProminentButtonModifier())
        .disabled(isBackingUp)
    }

    // MARK: - Disabled Content

    private var disabledContentView: some View {
        Text("Enable to automatically back up your vault to cloud storage whenever changes are made.")
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    // MARK: - Helpers

    private var borderColor: Color {
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
