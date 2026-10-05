import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers
import VaultBackup
import VaultFeed

/// Restore: items from a backup PDF, or from another device's transfer codes, after Touch ID or the Mac's password
/// (G31), with the backup's own password (G59). An empty vault imports; otherwise Merge or Replace, as on iOS.
struct VaultMacRestorePage: View {
    var services: VaultMacBackupServices
    @State var viewModel: BackupRestoreViewModel

    @State private var importing: ImportRequest?

    private struct ImportRequest: Identifiable {
        let id = UUID()
        var context: BackupImportContext
    }

    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        Group {
            switch viewModel.permissionState {
            case .allowed:
                choices
            case .undetermined, .denied:
                VaultMacBackupNotice(
                    systemImage: "key.horizontal",
                    title: viewModel.permissionState == .denied ? "Authentication Failed" : "Authenticate",
                    message: "Use Touch ID or your Mac's password to restore a backup.",
                    action: ("Authenticate", { Task { await viewModel.authenticate() } }),
                )
            case .unavailable:
                VaultMacBackupNotice(
                    systemImage: "lock.slash",
                    title: "Set Up a Mac Password",
                    message: "Restoring a backup needs Touch ID or your Mac's login password.",
                )
            }
        }
        .task {
            await services.dataModel.reloadHasVisibleItems()
        }
        // It asks again once the page closes, or Vault stops being the active app, as on iOS.
        .onDisappear {
            viewModel.lock()
        }
        .onChange(of: appearsActive) { _, isActive in
            if !isActive, importing == nil {
                viewModel.lock()
            }
        }
        .sheet(item: $importing, onDismiss: importDidClose) { request in
            VaultMacImportSheet(
                viewModel: BackupImportFlowViewModel(importContext: request.context, dataModel: services.dataModel),
                services: services,
                close: { importing = nil },
            )
        }
    }

    /// It asks again for the next import, and the choices follow what the vault holds now.
    private func importDidClose() {
        viewModel.lock()
        Task { await services.dataModel.reloadHasVisibleItems() }
    }

    private var choices: some View {
        Form {
            Section {
                if services.dataModel.hasVisibleItems {
                    choice(.merge, detail: "Add the backup's items to your vault. Items already here stay.")
                    choice(.override, detail: "Replace everything in your vault with the backup's items.")
                } else {
                    choice(.toEmptyVault, detail: "Import every item in the backup.")
                }
            } header: {
                Text("Restore Your Vault")
            } footer: {
                Text("Import from a PDF backup or another device. You'll need the password the backup was made with.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func choice(_ context: BackupImportContext, detail: String) -> some View {
        LabeledContent {
            Button(context.title + "…") {
                importing = ImportRequest(context: context)
            }
            .accessibilityIdentifier("backups.restore.\(context.identifier)")
        } label: {
            Text(context.title)
            Text(detail)
        }
    }
}

extension BackupImportContext {
    var title: String {
        switch self {
        case .toEmptyVault: "Import a Backup"
        case .merge: "Merge a Backup"
        case .override: "Replace Your Vault"
        }
    }

    var identifier: String {
        switch self {
        case .toEmptyVault: "import"
        case .merge: "merge"
        case .override: "replace"
        }
    }
}

/// Imports a backup: choose its PDF or scan its codes, enter its password, then import it.
struct VaultMacImportSheet: View {
    @State var viewModel: BackupImportFlowViewModel
    var services: VaultMacBackupServices
    var close: () -> Void
    /// Chooses a PDF, as the Open panel does unless a test says otherwise.
    var choosePDF: @MainActor () -> URL? = Self.runPDFPanel

    @State private var decryptedVaults = PassthroughSubject<VaultApplicationPayload, Never>()
    @State private var decryptor: BackupKeyDecryptorViewModel?
    @State private var isScanning = false
    @State private var isImporting = false

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                Spacer()
                if viewModel.importState.isFinished {
                    Button("Done", action: close)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("backups.import.done")
                } else {
                    Button("Cancel", role: .cancel, action: close)
                        .keyboardShortcut(.cancelAction)
                        .disabled(isImporting)
                }
            }
            .padding()
        }
        .frame(width: 520, height: 420)
        .onReceive(decryptedVaults) { payload in
            decryptor = nil
            viewModel.handleVaultDecoded(payload: payload)
        }
        .onChange(of: viewModel.payloadState) { _, state in
            if case let .needsPasswordEntry(vault) = state {
                decryptor = BackupKeyDecryptorViewModel(
                    encryptedVault: vault,
                    keyDeriverFactory: services.keyDeriverFactory,
                    encryptedVaultDecoder: services.encryptedVaultDecoder,
                    decryptedVaultSubject: decryptedVaults,
                )
            }
        }
        .sheet(isPresented: $isScanning) {
            VaultMacTransferScanner(intervalTimer: services.intervalTimer) { vault in
                isScanning = false
                Task { await viewModel.handleImport(fromEncryptedVault: vault) }
            } cancel: {
                isScanning = false
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        let context = viewModel.importContext
        if viewModel.importState.isFinished {
            VaultMacBackupNotice(
                systemImage: "checkmark.circle.fill",
                title: context.importedTitle,
                message: context.importedDescription,
            )
        } else if case let .ready(payload, _) = viewModel.payloadState {
            VaultMacBackupNotice(
                systemImage: "square.and.arrow.down",
                title: context.readyToImportTitle,
                message: context.readyToImportDescription + importError,
                action: isImporting ? nil : (context.importActionTitle, { importPayload(payload) }),
            )
            .overlay(alignment: .bottom) {
                if isImporting {
                    ProgressView(context.importingMessage)
                        .padding()
                }
            }
        } else if let decryptor {
            VaultMacBackupDecryptView(viewModel: decryptor) {
                self.decryptor = nil
                viewModel.cancelPasswordEntry()
            }
        } else {
            sources
        }
    }

    private var importError: String {
        guard case let .error(error) = viewModel.importState else { return "" }
        return "\n\n" + (error.userDescription ?? error.userTitle)
    }

    private var sources: some View {
        VStack(spacing: 16) {
            Image(systemName: viewModel
                .importContext == .override ? "exclamationmark.triangle.fill" : "square.and.arrow.down")
                .font(.system(size: 36))
                .foregroundStyle(viewModel.importContext == .override ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                .accessibilityHidden(true)
            Text(viewModel.importContext.title)
                .font(.title2.bold())
            Text(viewModel.importContext == .override
                ? "Everything in your vault will be replaced. You'll need the backup's password."
                : "Choose a PDF backup, or scan another device's codes. You'll need the backup's password.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            HStack {
                Button("Choose PDF…") { choose() }
                    .accessibilityIdentifier("backups.import.choose-pdf")
                Button("Scan Codes…") {
                    viewModel.clearError()
                    isScanning = true
                }
                .accessibilityIdentifier("backups.import.scan")
            }
            .controlSize(.large)
            if case let .error(error) = viewModel.payloadState {
                Text(error.userDescription ?? error.userTitle)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("backups.import.error")
            }
        }
        .padding(28)
    }

    private func choose() {
        viewModel.clearError()
        guard let url = choosePDF() else { return }
        Task {
            await viewModel.handleImport(fromPDF: Result { try Data(contentsOf: url) })
        }
    }

    private func importPayload(_ payload: VaultApplicationPayload) {
        isImporting = true
        Task {
            await viewModel.importPayload(payload: payload)
            isImporting = false
        }
    }

    /// The Open panel, for choosing one PDF.
    static func runPDFPanel() -> URL? {
        let panel = NSOpenPanel()
        VaultMacPanels.prepare(panel)
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Import"
        panel.message = "Choose a Vault backup PDF."
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// Asks for the backup's own password, and decrypts it. Deriving its key can take a few minutes.
struct VaultMacBackupDecryptView: View {
    @State var viewModel: BackupKeyDecryptorViewModel
    var cancel: () -> Void

    @State private var decryption: Task<Void, Never>?

    var body: some View {
        Form {
            Section {
                VaultMacSecureField(
                    "Backup Password",
                    text: $viewModel.enteredPassword,
                    identifier: "backups.import.password",
                )
                .disabled(viewModel.isDecrypting)
                HStack {
                    if viewModel.isDecrypting {
                        ProgressView()
                            .controlSize(.small)
                        Text("Decrypting the backup. This can take up to 3 minutes.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Back", role: .cancel) {
                        decryption?.cancel()
                        cancel()
                    }
                    Button("Decrypt") { decrypt() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!viewModel.canAttemptDecryption || viewModel.isDecrypting)
                        .accessibilityIdentifier("backups.import.decrypt")
                }
            } header: {
                Text("Decrypt Backup")
            } footer: {
                if case let .error(error) = viewModel.decryptionKeyState {
                    Text(error.userDescription ?? error.userTitle)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("backups.import.password-error")
                } else {
                    Text("Enter the password this backup was made with.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onDisappear { decryption?.cancel() }
    }

    private func decrypt() {
        guard viewModel.canAttemptDecryption, !viewModel.isDecrypting else { return }
        decryption = Task { await viewModel.attemptDecryption() }
    }
}

/// Scans another device's transfer codes with the Mac's camera or Continuity Camera, until it has every one.
struct VaultMacTransferScanner: View {
    var didScanVault: (EncryptedVault) -> Void
    var cancel: () -> Void

    @State private var handler: BackupImportScanningHandler
    @State private var manager: CodeScanningManager<BackupImportScanningHandler>
    @State private var problem: String?

    init(
        intervalTimer: any IntervalTimer,
        didScanVault: @escaping (EncryptedVault) -> Void,
        cancel: @escaping () -> Void,
    ) {
        let handler = BackupImportScanningHandler()
        _handler = State(initialValue: handler)
        _manager = State(initialValue: CodeScanningManager(intervalTimer: intervalTimer, handler: handler))
        self.didScanVault = didScanVault
        self.cancel = cancel
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Hold the other device's codes up to the camera.")
                .font(.headline)
            VaultMacQRCodeScanner { text in
                manager.scan(text: text)
            } didFail: { failure in
                problem = failure.message
            }
            .frame(width: 480, height: 360)
            .clipShape(.rect(cornerRadius: 8))
            Text(progress)
                .font(.callout)
                .foregroundStyle(problem == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
                .monospacedDigit()
                .accessibilityIdentifier("backups.scan.progress")
            Button("Cancel", role: .cancel, action: cancel)
                .keyboardShortcut(.cancelAction)
        }
        .padding()
        .onAppear { manager.startScanning() }
        .onDisappear { manager.disable() }
        .onReceive(manager.itemScannedPublisher()) { vault in
            didScanVault(vault)
        }
    }

    private var progress: String {
        if let problem {
            return problem
        }
        guard let state = handler.shardState else { return "No codes scanned yet." }
        return "Scanned \(state.collectedShardIndexes.count) of \(state.totalNumberOfShards) codes."
    }
}
