import AppKit
import SwiftUI
import VaultFeed

/// Auto-Backup: an encrypted PDF of the vault, written to a folder the user chooses, such as one in iCloud Drive,
/// whenever the vault changes, kept and cleaned up as on iOS (G62). Vault keeps the folder across launches with a
/// security-scoped bookmark.
struct VaultMacAutoBackupPage: View {
    @State var viewModel: AutoBackupViewModel
    /// Chooses a folder, as the Open panel does unless a test says otherwise.
    var chooseFolder: @MainActor () -> URL? = Self.runFolderPanel

    @State private var pendingRetention: AutoBackupRetention?

    var body: some View {
        Form {
            Section {
                Toggle("Auto-Backup", isOn: Binding(
                    get: { viewModel.configuration.isEnabled },
                    set: { enabled in Task { await viewModel.setEnabled(enabled) } },
                ))
                .accessibilityIdentifier("backups.auto.enabled")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(
                        "Backups are saved as encrypted PDFs in a folder you choose, such as one in iCloud Drive, whenever your vault changes.",
                    )
                    if let error = viewModel.configureError {
                        errorLabel(error)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            if viewModel.configuration.isEnabled {
                if viewModel.isDestinationConfigured {
                    settingsSection
                    activitySection
                } else {
                    Section {
                        Button("Choose Folder…") {
                            Task { await choose() }
                        }
                        .accessibilityIdentifier("backups.auto.choose-folder")
                    } footer: {
                        Text("Choose where backups are saved. Vault can only write to the folder you choose.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task {
            await viewModel.onAppear()
        }
        .confirmationDialog(
            "Delete Older Backups?",
            isPresented: Binding(get: { pendingRetention != nil }, set: {
                if !$0 {
                    pendingRetention = nil
                }
            }),
            presenting: pendingRetention,
        ) { retention in
            Button("Keep Backups for \(retention.localizedTitle)", role: .destructive) {
                Task { await viewModel.setRetention(retention) }
            }
        } message: { retention in
            Text(viewModel.confirmationMessage(toKeepBackupsFor: retention))
        }
    }

    private var settingsSection: some View {
        Section {
            LabeledContent("Save To") {
                HStack {
                    Text(viewModel.destinationName)
                        .accessibilityIdentifier("backups.auto.folder")
                    Button("Change…") {
                        Task { await choose() }
                    }
                }
            }
            Picker("Keep Backups For", selection: Binding(
                get: { viewModel.configuration.retentionDays },
                set: { retention in
                    if viewModel.needsConfirmation(toKeepBackupsFor: retention) {
                        pendingRetention = retention
                    } else {
                        Task { await viewModel.setRetention(retention) }
                    }
                },
            )) {
                ForEach(AutoBackupRetention.allCases, id: \.self) { retention in
                    Text(retention.localizedTitle).tag(retention)
                }
            }
        } header: {
            Text("Settings")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.scheduleSummary)
                if let error = viewModel.configureError {
                    errorLabel(error)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private var activitySection: some View {
        Section {
            if let run = viewModel.currentRun {
                LabeledContent(run.progress.phase.localizedTitle) {
                    ProgressView(value: run.progress.fractionCompleted)
                        .frame(width: 160)
                }
            } else if case .cleaningUp = viewModel.status {
                LabeledContent("Deleting old backups…") {
                    ProgressView()
                        .controlSize(.small)
                }
            } else {
                LabeledContent("Last Backup") {
                    Text(viewModel.lastBackupDate?.formatted(date: .abbreviated, time: .shortened)
                        ?? "No automatic backups yet")
                }
                if viewModel.showsBackupCompleteNotice {
                    Label("Backup Complete", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button("Back Up Now") {
                        Task { await viewModel.backupNow() }
                    }
                    .disabled(viewModel.isBackingUp)
                    .accessibilityIdentifier("backups.auto.back-up-now")
                }
            }
        } header: {
            Text(viewModel.currentRun == nil ? "Activity" : "Backing Up")
        }
    }

    private func errorLabel(_ error: AutoBackupError) -> some View {
        Label(
            [error.errorDescription, error.recoverySuggestion].compactMap(\.self).joined(separator: ". "),
            systemImage: "exclamationmark.triangle.fill",
        )
        .foregroundStyle(.orange)
    }

    private func choose() async {
        await viewModel.beginDestinationSelection()
        guard let url = chooseFolder() else { return }
        await viewModel.configureDestination(url: url)
    }

    /// The Open panel, for choosing one folder.
    static func runFolderPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose a folder for Vault's backups, such as one in iCloud Drive."
        return panel.runModal() == .OK ? panel.url : nil
    }
}
