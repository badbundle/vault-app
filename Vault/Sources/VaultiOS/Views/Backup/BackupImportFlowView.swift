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
            switch viewModel.payloadState {
            case .none, .ready, .needsPasswordEntry:
                EmptyView()
            case let .error(presentationError):
                errorSection(error: presentationError)
            }

            automaticImportSection
            qrCodeImportSection
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

    // MARK: - Import Source Sections

    private var automaticImportSection: some View {
        Section {
            ProminentActionButton("Select PDF File", systemImage: "doc.badge.arrow.up.fill") {
                isImporting = true
            }
        } header: {
            Text("Automatic Import")
        } footer: {
            Text("Select your Vault Export PDF from your files.")
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
    }

    private var qrCodeImportSection: some View {
        Section {
            ProminentActionButton("Start Scanning", systemImage: "qrcode.viewfinder") {
                modal = .cameraScanning
            }
        } header: {
            Text("QR Code Import")
        } footer: {
            Text("Use your camera to scan the QR codes from a PDF backup or another device.")
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
