import Foundation
import SwiftUI
import VaultFeed
import VaultKeygen

/// Screen for exporting the vault: a PDF backup to keep, or a one-off transfer to another device
/// by QR codes. Both carry the whole vault, encrypted with the backup password.
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
            headerSection

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
                            defaults: injector.defaults,
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
                BackupKeyChangeView(viewModel: .init(
                    dataModel: dataModel,
                    authenticationService: authenticationService,
                    deriverFactory: injector.vaultKeyDeriverFactory,
                ))
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

    // MARK: - Header Section

    /// What exporting is for, and what every option has in common, before the options themselves.
    private var headerSection: some View {
        Section {
            BackupHeroHeader(
                title: "Export Your Vault",
                subtitle: "Take a copy of your whole vault, encrypted with your backup password. You'll need that password to restore it.",
                systemImage: "square.and.arrow.up.fill",
                color: .accentColor,
                iconSize: 56,
            )
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
            Text("Exports are encrypted with your backup password, so you'll need to set one up first.")
        }
    }

    // MARK: - PDF Backup Section

    /// A backup to keep: a file that outlasts this device.
    private func pdfBackupSection(password: DerivedEncryptionKey) -> some View {
        Section {
            exportOption(
                title: "PDF Backup",
                detail: "An encrypted file you can save or print.",
                systemImage: "doc.text.fill",
                color: .accentColor,
            ) {
                modal = .pdfBackup(password)
            }
        } header: {
            Text("Keep a Backup")
        } footer: {
            Text(
                "Keep it somewhere safe, like iCloud Drive or a paper copy stored away from home. You can restore from it at any time, on any device.",
            )
        }
    }

    // MARK: - Device Transfer Section

    /// A move, not a backup: the codes only exist while this screen shows them.
    private func deviceTransferSection(password: DerivedEncryptionKey) -> some View {
        Section {
            exportOption(
                title: "Transfer with QR Codes",
                detail: "Show codes for another device to scan, without saving a file.",
                systemImage: "qrcode",
                color: .indigo,
            ) {
                modal = .deviceTransfer(password)
            }
        } header: {
            Text("Move to Another Device")
        } footer: {
            Text(
                "On the other device, open Backups, choose Restore and scan the codes. Keep both devices nearby until it's done.",
            )
        }
    }

    // MARK: - Export Option

    /// One way to export, as a row that says what it makes, in the style of the rows on the Backups screen.
    private func exportOption(
        title: String,
        detail: String,
        systemImage: String,
        color: Color,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            FormRow(image: Image(systemName: systemImage), color: color) {
                HStack {
                    TextAndSubtitle(title: title, subtitle: detail)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
        }
        .tint(.primary)
    }
}
