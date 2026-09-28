import CodeScanner
import Foundation
import SwiftUI
import VaultBackup
import VaultFeed

/// Scans a backup's QR codes, from a PDF backup or another device's Export screen, in any order.
///
/// Each new code ticks off its tile with a light tap, and the last one plays the success haptic before the sheet
/// moves on.
@MainActor
struct BackupImportCodeScannerView: View {
    @State private var scanner: CodeScanningManager<BackupImportScanningHandler>
    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isCodeImagePickerGalleryVisible = false
    @State private var handler: BackupImportScanningHandler
    var loadedEncryptedVault: (EncryptedVault) async -> Void

    init(
        intervalTimer: any IntervalTimer,
        handler: BackupImportScanningHandler = BackupImportScanningHandler(),
        loadedEncryptedVault: @escaping (EncryptedVault) async -> Void,
    ) {
        scanner = CodeScanningManager(intervalTimer: intervalTimer, handler: handler)
        self.handler = handler
        self.loadedEncryptedVault = loadedEncryptedVault
    }

    var body: some View {
        Form {
            headlineSection
            if let state = handler.shardState {
                progressSection(state: state)
            }
        }
        .navigationTitle(Text("Scan Backup"))
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(scanner.hasPartialState)
        .animation(reduceMotion ? .easeInOut(duration: 0.25) : .snappy, value: scannedCount)
        .sensoryFeedback(.impact(weight: .light), trigger: scannedCount) { oldValue, newValue in
            // Only for a new code, as a code scanned again changes nothing. The last one has the success haptic.
            newValue > oldValue && newValue < totalCount
        }
        .sensoryFeedback(.success, trigger: scanner.scanningState) { _, newValue in
            newValue == .success(.complete)
        }
        .sensoryFeedback(.error, trigger: scanner.scanningState) { _, newValue in
            newValue == .failure(.unrecoverable)
        }
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

    private var scannedCount: Int {
        handler.shardState?.collectedShardIndexes.count ?? 0
    }

    private var totalCount: Int {
        handler.shardState?.totalNumberOfShards ?? 0
    }

    // MARK: - Headline Section

    /// What to scan, under the camera. Smaller than the other screens' headers: the camera is the hero here.
    private var headlineSection: some View {
        Section {
            VStack(spacing: 6) {
                Text("Scan the QR Codes")
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                Text("From a PDF backup, or the Export screen on another device. Any order works.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .noListBackground()
        } header: {
            CodeScanningView(
                scanner: scanner,
                isImagePickerVisible: $isCodeImagePickerGalleryVisible,
            )
            .padding()
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Progress Section

    private func progressSection(state: BackupImportScanningHandler.State) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(state.collectedShardIndexes.count) of \(state.totalNumberOfShards) scanned")
                    .font(.headline)
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .opacity : .numericText())
                ProgressView(
                    value: Double(state.collectedShardIndexes.count),
                    total: Double(state.totalNumberOfShards),
                )
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)

            // The line above says the same for VoiceOver.
            BackupImportCodeStateVisualizerView(
                totalCount: state.totalNumberOfShards,
                selectedIndexes: state.collectedShardIndexes,
            )
            .padding(.vertical, 4)
            .accessibilityHidden(true)
        }
    }
}
