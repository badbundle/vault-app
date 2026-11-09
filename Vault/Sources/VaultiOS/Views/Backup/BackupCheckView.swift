import Combine
import Foundation
import FoundationExtensions
import SwiftUI
import VaultBackup
import VaultFeed

/// Checks that a backup opens with its password, without restoring it: choose its PDF or scan its QR codes, then
/// enter its password.
///
/// It says only that the backup opened, and changes nothing on the device (`BackupCheckViewModel`). It reads neither
/// the vault nor the backup key, so unlike Restore it doesn't ask for Face ID or the passcode first.
@MainActor
struct BackupCheckView: View {
    @Environment(VaultInjector.self) private var injector
    @State private var viewModel: BackupCheckViewModel
    @State private var isChoosingPDF = false
    @State private var modal: Modal?
    @State private var decryptedVaultSubject = PassthroughSubject<VaultApplicationPayload, Never>()

    init(viewModel: BackupCheckViewModel) {
        _viewModel = .init(wrappedValue: viewModel)
    }

    private enum Modal: IdentifiableSelf {
        case enterPassword(EncryptedVault)
        case cameraScanning
    }

    var body: some View {
        Form {
            headerSection
            sourcesSection
        }
        .navigationTitle(Text("Check a Backup"))
        .navigationBarTitleDisplayMode(.inline)
        .animation(.snappy, value: viewModel.state)
        .sensoryFeedback(.success, trigger: viewModel.state) { _, newValue in
            newValue.isOpened
        }
        .sheet(item: $modal, onDismiss: { viewModel.cancelPasswordEntry() }, content: { item in
            switch item {
            case let .enterPassword(encryptedVault):
                NavigationStack {
                    BackupKeyDecryptorView(viewModel: .init(
                        encryptedVault: encryptedVault,
                        keyDeriverFactory: injector.vaultKeyDeriverFactory,
                        encryptedVaultDecoder: injector.encryptedVaultDecoder,
                        decryptedVaultSubject: decryptedVaultSubject,
                    ))
                    .navigationBarTitleDisplayMode(.inline)
                }
            case .cameraScanning:
                NavigationStack {
                    BackupImportCodeScannerView(
                        intervalTimer: injector.intervalTimer,
                        loadedEncryptedVault: {
                            modal = nil
                            viewModel.check(encryptedVault: $0)
                        },
                    )
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
        })
        // The backup opened. What it held is dropped here: the check only says that it opened.
        .onReceive(decryptedVaultSubject) { @MainActor _ in
            viewModel.backupDidOpen()
        }
        .onChange(of: viewModel.state) { _, newValue in
            if case let .needsPasswordEntry(encryptedVault) = newValue {
                modal = .enterPassword(encryptedVault)
            }
        }
    }

    // MARK: - Header Section

    /// What the check does, then that the backup opened, or why it couldn't be read, in the same place.
    private var headerSection: some View {
        BackupImportHeaderSection(
            title: viewModel.state.isOpened ? "This Backup Opens" : "Check a Backup",
            subtitle: viewModel.state.isOpened
                ? "Its password is right, and everything in it can be restored. Nothing on this device was changed."
                : "Make sure a backup opens with its password, without restoring it. Nothing on this device changes.",
            systemImage: viewModel.state.isOpened ? "checkmark.circle.fill" : "doc.text.magnifyingglass",
            color: viewModel.state.isOpened ? .green : .accentColor,
            error: error,
        )
    }

    private var error: PresentationError? {
        switch viewModel.state {
        case let .error(error): error
        case .none, .needsPasswordEntry, .opened: nil
        }
    }

    // MARK: - Sources Section

    /// Where the backup comes from, as on the import sheet.
    private var sourcesSection: some View {
        Section {
            BackupOptionRow(
                title: "Choose a PDF Backup",
                detail: "A PDF backup or an auto-backup, from Files.",
                systemImage: "doc.text.fill",
                color: .accentColor,
            ) {
                viewModel.clearResult()
                isChoosingPDF = true
            }
            .fileImporter(isPresented: $isChoosingPDF, allowedContentTypes: [.pdf]) { result in
                Task {
                    await viewModel.check(pdf: result.tryMap { url in
                        _ = url.startAccessingSecurityScopedResource()
                        defer { url.stopAccessingSecurityScopedResource() }
                        return try Data(contentsOf: url)
                    })
                }
            }

            BackupOptionRow(
                title: "Scan QR Codes",
                detail: "From a printed PDF backup.",
                systemImage: "qrcode.viewfinder",
                color: .indigo,
            ) {
                viewModel.clearResult()
                modal = .cameraScanning
            }
        } footer: {
            Text("The backup is opened only to check it, then forgotten. Nothing in it is added to your vault.")
        }
    }
}
