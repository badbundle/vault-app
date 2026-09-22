import Foundation
import SwiftUI
import VaultFeed
import VaultKeygen

/// Screen for exporting the vault: PDF backup and device transfer.
@MainActor
struct BackupExportView: View {
    @Environment(VaultDataModel.self) var dataModel
    @Environment(DeviceAuthenticationService.self) var authenticationService
    @Environment(VaultInjector.self) var injector
    @State private var modal: Modal?
    @State private var pdfNavigationPath = NavigationPath()

    enum Modal: IdentifiableSelf {
        case updatePassword
        case pdfBackup(DerivedEncryptionKey)
        case deviceTransfer(DerivedEncryptionKey)
    }

    var body: some View {
        Form {
            switch dataModel.backupPassword {
            case .error:
                authenticateSection(isError: true)
            case .notFetched:
                authenticateSection(isError: false)
            case .notCreated:
                passwordNotCreatedSection
            case let .fetched(password):
                pdfBackupSection(password: password)
                deviceTransferSection(password: password)
            }
        }
        .navigationTitle(Text("Export"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await dataModel.reloadItems()
        }
        .sheet(item: $modal, onDismiss: nil) { sheet in
            switch sheet {
            case let .pdfBackup(password):
                NavigationStack(path: $pdfNavigationPath) {
                    BackupCreatePDFView(
                        viewModel: .init(
                            backupPassword: password,
                            dataModel: dataModel,
                            clock: injector.clock,
                            backupEventLogger: injector.backupEventLogger,
                            defaults: injector.defaults,
                            fileManager: injector.fileManager,
                        ),
                        navigationPath: $pdfNavigationPath,
                    )
                    .navigationDestination(for: BackupCreatePDFViewModel.GeneratedPDF.self, destination: { pdf in
                        BackupGeneratedPDFView(pdf: pdf) {
                            modal = nil
                        }
                        .onDisappear {
                            // Reset PDF navigation path so next generation starts from the beginning
                            pdfNavigationPath.removeLast(pdfNavigationPath.count)
                        }
                    })
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button {
                                modal = nil
                            } label: {
                                Text("Cancel")
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
            case .updatePassword:
                NavigationStack {
                    BackupKeyChangeView(viewModel: .init(
                        dataModel: dataModel,
                        authenticationService: authenticationService,
                        deriverFactory: injector.vaultKeyDeriverFactory,
                    ))
                }
            case let .deviceTransfer(password):
                NavigationStack {
                    DeviceTransferExportView(
                        viewModel: .init(
                            backupPassword: password,
                            dataModel: dataModel,
                            clock: injector.clock,
                            backupEventLogger: injector.backupEventLogger,
                            intervalTimer: injector.intervalTimer,
                        ),
                    )
                }
            }
        }
    }

    // MARK: - Authenticate Section

    private func authenticateSection(isError: Bool) -> some View {
        Section {
            ProminentActionButton("Authenticate", systemImage: "key.horizontal.fill") {
                await dataModel.loadBackupPassword()
            }
        } header: {
            Text(isError ? "Authentication Failed" : "Locked")
        } footer: {
            Text(
                isError
                    ? "Unable to verify your identity. Please try again."
                    : "Authenticate to export your vault.",
            )
            .foregroundStyle(isError ? Color.red : Color.secondary)
        }
    }

    // MARK: - Password Not Created Section

    private var passwordNotCreatedSection: some View {
        Section {
            Button {
                modal = .updatePassword
            } label: {
                FormRow(image: Image(systemName: "key.horizontal.fill"), color: .accentColor) {
                    Text("Create Backup Password")
                }
            }
        } header: {
            Text("Backup Password")
        } footer: {
            Text("Create a backup password to protect your vault backups.")
        }
    }

    // MARK: - PDF Backup Section

    private func pdfBackupSection(password: DerivedEncryptionKey) -> some View {
        Section {
            ProminentActionButton("Create PDF Backup", systemImage: "printer.filled.and.paper") {
                modal = .pdfBackup(password)
            }
        } header: {
            Text("PDF Backup")
        } footer: {
            Text("Create an offline backup you can print or save.")
        }
    }

    // MARK: - Device Transfer Section

    private func deviceTransferSection(password: DerivedEncryptionKey) -> some View {
        Section {
            ProminentActionButton("Start Transfer", systemImage: "qrcode") {
                modal = .deviceTransfer(password)
            }
        } header: {
            Text("Transfer to Another Device")
        } footer: {
            Text("Display QR codes to scan with another device.")
        }
    }
}
