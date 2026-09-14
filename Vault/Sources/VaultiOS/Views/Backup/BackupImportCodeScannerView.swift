import CodeScanner
import Foundation
import SwiftUI
import VaultBackup
import VaultFeed

@MainActor
struct BackupImportCodeScannerView: View {
    @State private var scanner: CodeScanningManager<BackupImportScanningHandler>
    @Environment(\.presentationMode) private var presentationMode
    @State private var isCodeImagePickerGalleryVisible = false
    @State private var handler: BackupImportScanningHandler
    var loadedEncryptedVault: (EncryptedVault) async -> Void

    init(intervalTimer: any IntervalTimer, loadedEncryptedVault: @escaping (EncryptedVault) async -> Void) {
        let handler = BackupImportScanningHandler()
        scanner = CodeScanningManager(intervalTimer: intervalTimer, handler: handler)
        self.handler = handler
        self.loadedEncryptedVault = loadedEncryptedVault
    }

    var body: some View {
        Form {
            section
        }
        .navigationTitle(Text("Import Vault"))
        .interactiveDismissDisabled(scanner.hasPartialState)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    Text("Cancel")
                        .foregroundStyle(.red)
                }
            }
        }
        .onAppear {
            scanner.startScanning()
        }
        .onDisappear {
            scanner.disable()
        }
        .onReceive(scanner.itemScannedPublisher()) { encryptedVault in
            Task { await loadedEncryptedVault(encryptedVault) }
        }
    }

    private var section: some View {
        Section {
            if let state = handler.shardState {
                LabeledContent("Total Codes", value: "\(state.totalNumberOfShards)")
                LabeledContent("Scanned Codes", value: "\(state.collectedShardIndexes.count)")
                BackupImportCodeStateVisualizerView(
                    totalCount: state.totalNumberOfShards,
                    selectedIndexes: state.collectedShardIndexes,
                )
                .padding(.horizontal)
                .containerRelativeFrame(.horizontal)
            } else {
                PlaceholderView(
                    systemIcon: "qrcode.viewfinder",
                    title: "Scan a QR code to start",
                    subtitle: "Face your camera at the codes located on your Vault export document.",
                )
                .padding()
                .containerRelativeFrame(.horizontal)
            }
        } header: {
            CodeScanningView(
                scanner: scanner,
                isImagePickerVisible: $isCodeImagePickerGalleryVisible,
            )
            .padding()
            .frame(maxWidth: .infinity)
        }
    }
}
