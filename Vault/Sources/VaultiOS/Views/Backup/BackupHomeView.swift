import Foundation
import SwiftUI
import VaultFeed

/// Hub for everything backup: status, auto-backup, export, restore, and the
/// backup password.
///
/// The hub itself is reachable without device authentication — it exposes
/// navigation and backup recency only. Every sub-surface that loads or uses
/// the backup key authenticates on entry.
@MainActor
struct BackupHomeView: View {
    @Environment(VaultDataModel.self) var dataModel
    @Environment(DeviceAuthenticationService.self) var authenticationService
    @Environment(VaultInjector.self) var injector
    @State private var isShowingPasswordSheet = false

    var body: some View {
        Form {
            summarySection
            autoBackupSection
            exportSection
            restoreSection
            passwordSection
        }
        .navigationTitle(Text("Backups"))
        .sheet(isPresented: $isShowingPasswordSheet) {
            NavigationStack {
                BackupKeyChangeView(viewModel: .init(
                    dataModel: dataModel,
                    authenticationService: authenticationService,
                    deriverFactory: injector.vaultKeyDeriverFactory,
                ))
            }
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
                    Text("Auto-Backup")
                }
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

    private var passwordSection: some View {
        Section {
            Button {
                isShowingPasswordSheet = true
            } label: {
                FormRow(image: Image(systemName: "key.horizontal.fill"), color: .accentColor) {
                    Text("Backup Password")
                }
            }
        } footer: {
            Text("Set or change the password that protects your backups.")
        }
    }
}
