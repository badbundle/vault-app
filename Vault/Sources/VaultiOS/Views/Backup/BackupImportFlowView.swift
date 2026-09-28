import Combine
import Foundation
import FoundationExtensions
import SwiftUI
import VaultBackup
import VaultFeed

@MainActor
struct BackupImportFlowView: View {
    @Environment(VaultInjector.self) private var injector
    @State private var viewModel: BackupImportFlowViewModel
    @State private var isImporting = false
    @State private var importTask: Task<Void, any Error>?
    @State private var navPath = NavigationPath()
    @State private var modal: Modal?
    @State private var decryptedVaultSubject = PassthroughSubject<VaultApplicationPayload, Never>()

    @Environment(\.dismiss) private var dismiss

    init(viewModel: BackupImportFlowViewModel) {
        self.viewModel = viewModel
    }

    private enum Modal: IdentifiableSelf {
        case generateDecryptionKey(EncryptedVault)
        case cameraScanning
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            rootContent
        }
        .interactiveDismissDisabled(!viewModel.importState.isFinished)
        .sheet(item: $modal, onDismiss: { viewModel.cancelPasswordEntry() }, content: { item in
            switch item {
            case let .generateDecryptionKey(encryptedVault):
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
                            await viewModel.handleImport(fromEncryptedVault: $0)
                        },
                    )
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
        })
        .onReceive(decryptedVaultSubject) { @MainActor vaultApplicationPayload in
            viewModel.handleVaultDecoded(payload: vaultApplicationPayload)
        }
        .onChange(of: viewModel.payloadState) { _, newValue in
            switch newValue {
            case let .ready(payload, _):
                navPath.append(payload)
            case let .needsPasswordEntry(encryptedVault):
                // Go straight to password entry. There is nothing to decide at this point — the
                // document is encrypted and the only way forward is the password — so an
                // intermediate screen would just add a tap.
                modal = .generateDecryptionKey(encryptedVault)
            case .none, .error:
                break
            }
        }
    }

    private var rootContent: some View {
        Form {
            sourceHeaderSection
            sourcesSection
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                }
                .foregroundStyle(Color.red)
            }
        }
        .animation(.snappy, value: viewModel.importState)
        .animation(.snappy, value: viewModel.payloadState)
        .navigationTitle(Text("Import"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: VaultApplicationPayload.self) { payload in
            readyToImportView(vaultApplicationPayload: payload)
        }
    }

    // MARK: - Error Section

    private func errorSection(error: PresentationError) -> some View {
        Section {
            PlaceholderView(
                systemIcon: "exclamationmark.triangle.fill",
                title: error.userTitle,
                subtitle: error.userDescription,
            )
            .padding()
            .containerRelativeFrame(.horizontal)
            .foregroundStyle(.red)
        }
    }

    // MARK: - Header Section

    /// What's about to happen to the vault, with the symbol of the Restore page's row that opened this sheet.
    private var sourceHeaderSection: some View {
        BackupImportHeaderSection(
            title: sourceTitle,
            subtitle: sourceSubtitle,
            systemImage: viewModel.importContext.systemImage,
            color: viewModel.importContext.color,
            error: payloadError,
        )
    }

    private var payloadError: PresentationError? {
        switch viewModel.payloadState {
        case let .error(error): error
        case .none, .needsPasswordEntry, .ready: nil
        }
    }

    private var sourceTitle: String {
        switch viewModel.importContext {
        case .toEmptyVault: "Import a Backup"
        case .merge: "Merge a Backup"
        case .override: "Replace Your Vault"
        }
    }

    private var sourceSubtitle: String {
        switch viewModel.importContext {
        case .toEmptyVault, .merge:
            "Choose a PDF or scan QR codes. You'll need the backup's password."
        case .override:
            "Everything on this device will be replaced. You'll need the backup's password."
        }
    }

    // MARK: - Sources Section

    /// Where the backup comes from, as rows in the style of the Export page's options.
    private var sourcesSection: some View {
        Section {
            BackupOptionRow(
                title: "Choose a PDF Backup",
                detail: "Pick the backup file from Files.",
                systemImage: "doc.text.fill",
                color: .accentColor,
            ) {
                viewModel.clearError()
                isImporting = true
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.pdf]) { result in
                importTask = Task {
                    await viewModel.handleImport(fromPDF: result.tryMap { url in
                        _ = url.startAccessingSecurityScopedResource()
                        defer { url.stopAccessingSecurityScopedResource() }
                        return try Data(contentsOf: url)
                    })
                }
            }

            BackupOptionRow(
                title: "Scan QR Codes",
                detail: "From a PDF backup, or the Export screen on another device.",
                systemImage: "qrcode.viewfinder",
                color: .indigo,
            ) {
                viewModel.clearError()
                modal = .cameraScanning
            }
        }
    }

    // MARK: - Ready to Import View

    private func readyToImportView(vaultApplicationPayload: VaultApplicationPayload) -> some View {
        Form {
            switch viewModel.importState {
            case .notStarted:
                readyToImportSection(payload: vaultApplicationPayload)
            case let .error(error):
                errorSection(error: error)
                importSection(vault: vaultApplicationPayload)
            case .success:
                successSection
            }
        }
        .animation(.snappy, value: viewModel.importState)
        .animation(.snappy, value: viewModel.payloadState)
        .toolbar {
            if viewModel.importState.isFinished {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                    }
                }
            }
        }
    }

    // MARK: - Ready to Import Section

    private func readyToImportSection(payload: VaultApplicationPayload) -> some View {
        Section {
            importRow(vault: payload)
        } header: {
            Text(viewModel.importContext.readyToImportTitle)
        } footer: {
            Text(viewModel.importContext.readyToImportDescription)
        }
    }

    private func importSection(vault: VaultApplicationPayload) -> some View {
        Section {
            importRow(vault: vault)
        }
    }

    // MARK: - Success Section

    private var successSection: some View {
        Section {
            PlaceholderView(
                systemIcon: "checkmark.circle.fill",
                title: "Imported",
                subtitle: "Your vault has been updated with the items from this backup.",
            )
            .padding()
            .containerRelativeFrame(.horizontal)
        }
    }

    // MARK: - Import Row

    private func importRow(vault: VaultApplicationPayload) -> some View {
        ProminentActionButton("Import Now", systemImage: "square.and.arrow.down") {
            await viewModel.importPayload(payload: vault)
        }
    }
}

// MARK: - BackupImportHeaderSection

/// An import screen's hero header, or the error in its place: a red cross replaces the symbol, the error's title and
/// description replace the header's, and the error haptic plays.
///
/// One header either way, so the symbol is replaced in place rather than the whole header swapped out.
struct BackupImportHeaderSection: View {
    var title: String
    var subtitle: String
    var systemImage: String
    var color: Color
    var error: PresentationError?

    var body: some View {
        Section {
            BackupHeroHeader(
                title: error?.userTitle ?? title,
                subtitle: error.map { $0.userDescription ?? "" } ?? subtitle,
                systemImage: error == nil ? systemImage : "xmark.octagon.fill",
                color: error == nil ? color : .red,
                iconSize: 56,
            )
            .sensoryFeedback(.error, trigger: error) { _, newValue in
                newValue != nil
            }
            .onChange(of: error) { _, newValue in
                if let newValue {
                    AccessibilityNotification.Announcement(newValue.userTitle).post()
                }
            }
        }
    }
}

// MARK: - BackupImportContext

extension BackupImportContext {
    /// The symbol for this kind of import, on the Restore page's row and on the import sheet that it opens.
    var systemImage: String {
        switch self {
        case .toEmptyVault: "square.and.arrow.down"
        case .merge: "square.and.arrow.down.on.square"
        case .override: "exclamationmark.triangle.fill"
        }
    }

    /// Red for replacing the vault, which deletes anything that isn't in the backup.
    var color: Color {
        switch self {
        case .toEmptyVault, .merge: .accentColor
        case .override: .red
        }
    }
}
