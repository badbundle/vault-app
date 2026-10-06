import SwiftUI
import VaultFeed

/// The Backups page that's open, in the window's detail column.
struct VaultMacBackupsDetail: View {
    var page: VaultMacBackupsPage?
    var services: VaultMacBackupServices

    @State private var isShowingPasswordSheet = false

    var body: some View {
        Group {
            switch page {
            case .autoBackup:
                gate(purpose: "Use Touch ID or your Mac's password to set up Auto-Backup.") { _ in
                    VaultMacAutoBackupPage(viewModel: AutoBackupViewModel(service: services.autoBackupService))
                }
            case .keepABackup:
                gate(purpose: "Use Touch ID or your Mac's password to make a backup of your vault.") { key in
                    VaultMacKeepABackupPage(
                        viewModel: BackupCreatePDFViewModel(
                            backupPassword: key,
                            dataModel: services.dataModel,
                            clock: services.clock,
                            defaults: services.defaults,
                            hintStorage: services.hintStorage,
                        ),
                        saver: VaultMacBackupPDFSaver(backupEventLogger: services.backupEventLogger),
                    )
                }
            case .transfer:
                gate(purpose: "Use Touch ID or your Mac's password to move your vault to another device.") { key in
                    VaultMacTransferPage(viewModel: DeviceTransferExportViewModel(
                        backupPassword: key,
                        dataModel: services.dataModel,
                        clock: services.clock,
                        intervalTimer: services.intervalTimer,
                    ))
                }
            case .restore:
                VaultMacRestorePage(
                    services: services,
                    viewModel: BackupRestoreViewModel(authenticationService: services.authentication),
                )
            case .password:
                VaultMacBackupPasswordPage(services: services, isShowingPasswordSheet: $isShowingPasswordSheet)
            case nil:
                ContentUnavailableView("Backups", systemImage: "externaldrive")
            }
        }
        .id(page)
        .sheet(isPresented: $isShowingPasswordSheet) {
            VaultMacBackupPasswordSheet(
                viewModel: BackupKeyChangeViewModel(
                    dataModel: services.dataModel,
                    authenticationService: services.authentication,
                    deriverFactory: services.keyDeriverFactory,
                ),
                close: { isShowingPasswordSheet = false },
            )
        }
    }

    private func gate(
        purpose: String,
        @ViewBuilder content: @escaping (DerivedEncryptionKey) -> some View,
    ) -> some View {
        VaultMacBackupKeyGate(
            services: services,
            purpose: purpose,
            setUpPassword: { isShowingPasswordSheet = true },
            content: content,
        )
    }
}
