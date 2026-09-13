import Foundation
import SwiftUI
import VaultFeed
import VaultKeygen

@MainActor
struct BackupCreateView: View {
    @Environment(VaultDataModel.self) var dataModel
    @Environment(DeviceAuthenticationService.self) var authenticationService
    @Environment(VaultInjector.self) var injector
    @State private var viewModel = BackupCreateViewModel()
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
                passwordExistsSection
                AutoBackupSettingsView(autoBackupService: injector.autoBackupService)
                pdfBackupSection(password: password)
                deviceTransferSection(password: password)
            }
        }
        .navigationTitle(Text(viewModel.strings.homeTitle))
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
            AsyncButton {
                await dataModel.loadBackupPassword()
            } label: {
                FormRow(image: Image(systemName: "key.horizontal.fill"), color: .accentColor) {
                    Text("Authenticate")
                }
            } loading: {
                FormRow(image: Image(systemName: "key.horizontal.fill"), color: .accentColor) {
                    ProgressView()
                }
            }
        } header: {
            Text(
                isError
                    ? viewModel.strings.backupPasswordErrorTitle
                    : viewModel.strings.backupPasswordLoadingTitle,
            )
        } footer: {
            Text(
                isError
                    ? viewModel.strings.backupPasswordErrorDetail
                    : "Authenticate to access backup settings.",
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

    // MARK: - Password Exists Section

    private var passwordExistsSection: some View {
        Section {
            LabeledContent {
                Text("Active")
            } label: {
                FormRow(image: Image(systemName: "checkmark.shield.fill"), color: .green) {
                    Text("Backup Password")
                }
            }

            Button {
                modal = .updatePassword
            } label: {
                FormRow(image: Image(systemName: "key.2.on.ring.fill"), color: .gray) {
                    Text("Change Password")
                }
            }
        } footer: {
            Text("Your backups are protected with encryption.")
        }
    }

    // MARK: - PDF Backup Section

    private func pdfBackupSection(password: DerivedEncryptionKey) -> some View {
        Section {
            Button {
                modal = .pdfBackup(password)
            } label: {
                FormRow(image: Image(systemName: "printer.filled.and.paper"), color: .accentColor) {
                    Text("Create PDF Backup")
                }
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
            Button {
                modal = .deviceTransfer(password)
            } label: {
                FormRow(image: Image(systemName: "qrcode"), color: .accentColor) {
                    Text("Start Transfer")
                }
            }
        } header: {
            Text("Transfer to Another Device")
        } footer: {
            Text("Display QR codes to scan with another device.")
        }
    }
}
