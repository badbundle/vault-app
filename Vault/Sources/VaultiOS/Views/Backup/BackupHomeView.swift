import Foundation
import SwiftUI
import VaultFeed

/// Hub for everything backup: status, auto-backup, export, restore, and the
/// backup password.
///
/// The hub itself is reachable without device authentication — it exposes
/// navigation, backup recency and whether a backup password is set only.
/// Every sub-surface that loads or uses the backup key authenticates on entry.
@MainActor
struct BackupHomeView: View {
    @Environment(VaultDataModel.self) var dataModel
    @Environment(DeviceAuthenticationService.self) var authenticationService
    @Environment(VaultInjector.self) var injector
    @State private var isShowingPasswordSheet = false
    /// The latest value from the service's configuration publisher, which doesn't replay.
    @State private var publishedAutoBackupEnabled: Bool?

    private var isAutoBackupEnabled: Bool {
        publishedAutoBackupEnabled ?? injector.autoBackupService.configuration.isEnabled
    }

    var body: some View {
        Form {
            summarySection
            autoBackupSection
            exportSection
            restoreSection
            passwordSection
        }
        .navigationTitle(Text("Backups"))
        .task {
            await dataModel.loadBackupPasswordStatus()
        }
        .sheet(isPresented: $isShowingPasswordSheet) {
            BackupKeyChangeView(viewModel: .init(
                dataModel: dataModel,
                authenticationService: authenticationService,
                deriverFactory: injector.vaultKeyDeriverFactory,
            ))
        }
    }

    // MARK: - Summary Section

    private var summarySection: some View {
        Section {
            LastBackupSummaryView(lastBackup: dataModel.lastBackupEvent)
                .listRowInsets(EdgeInsets())
        }
    }

    // MARK: - Auto-Backup Section

    private var autoBackupSection: some View {
        Section {
            NavigationLink {
                AutoBackupView(viewModel: .init(service: injector.autoBackupService))
            } label: {
                FormRow(image: Image(systemName: "arrow.clockwise.icloud"), color: .accentColor) {
                    LabeledContent {
                        Text(isAutoBackupEnabled ? "On" : "Off")
                    } label: {
                        Text("Auto-Backup")
                    }
                }
            }
            .onReceive(injector.autoBackupService.configurationPublisher) { configuration in
                publishedAutoBackupEnabled = configuration.isEnabled
            }
        } footer: {
            Text("Automatically back up your vault to cloud storage when changes are made.")
        }
    }

    // MARK: - Export Section

    private var exportSection: some View {
        Section {
            NavigationLink {
                BackupExportView()
            } label: {
                FormRow(image: Image(systemName: "square.and.arrow.up.fill"), color: .accentColor) {
                    Text("Export")
                }
            }
        } footer: {
            Text("Create a PDF backup or transfer to another device.")
        }
    }

    // MARK: - Restore Section

    private var restoreSection: some View {
        Section {
            NavigationLink {
                BackupRestoreView()
            } label: {
                FormRow(image: Image(systemName: "square.and.arrow.down.fill"), color: .accentColor) {
                    Text("Restore")
                }
            }
        } footer: {
            Text("Import items from a backup PDF or another device.")
        }
    }

    // MARK: - Password Section

    @ViewBuilder
    private var passwordSection: some View {
        let status = dataModel.backupPasswordStatus
        Section {
            BackupPasswordStatusRow(status: status)

            Button {
                isShowingPasswordSheet = true
            } label: {
                switch status {
                case .unknown:
                    // Without a status row above it, the button names the feature itself.
                    FormRow(image: Image(systemName: "key.horizontal.fill"), color: .accentColor) {
                        Text("Backup Password")
                    }
                case .notSet:
                    Text("Set Up Backup Password")
                case .set:
                    Text("Change Backup Password")
                }
            }
        } footer: {
            switch status {
            case .unknown:
                Text("Set or change the password that protects your backups.")
            case .notSet, .set:
                Text("Backups are encrypted with this password. You'll need it to restore them.")
            }
        }
        .animation(.default, value: status)
    }
}
