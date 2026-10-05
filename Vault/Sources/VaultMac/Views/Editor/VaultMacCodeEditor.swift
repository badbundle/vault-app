import SwiftUI
import VaultCore
import VaultFeed

/// Adds or edits a code, with the shared editor's model, as the iOS app's does: the same fields and the same checks
/// before it's saved (G77). A new code's key is typed in, scanned with the camera, or read from an image file.
struct VaultMacCodeEditor: View {
    @State var viewModel: OTPCodeDetailViewModel
    var close: () -> Void

    @State private var isScanning = false
    @State private var scanProblem: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                if viewModel.isInitialCreation {
                    keySection
                }
                Section("Details") {
                    VaultMacTextField(
                        "Site Name",
                        text: $viewModel.editingModel.detail.issuerTitle,
                        identifier: "editor.issuer",
                    )
                    VaultMacTextField(
                        "Account",
                        text: $viewModel.editingModel.detail.accountNameTitle,
                        identifier: "editor.account",
                    )
                    VaultMacTextField("Description", text: $viewModel.editingModel.detail.description)
                }
                VaultMacAppearanceSection(
                    color: $viewModel.editingModel.detail.color,
                    tags: $viewModel.editingModel.detail.tags,
                    allTags: viewModel.allTags,
                )
                VaultMacPrivacySection(
                    viewConfig: $viewModel.editingModel.detail.viewConfig,
                    searchPassphrase: $viewModel.editingModel.detail.searchPassphrase,
                    hasExistingSearchPassphrase: viewModel.editingModel.detail.hasExistingSearchPassphrase,
                    killphraseEnabled: $viewModel.editingModel.detail.killphraseEnabled,
                    newKillphrase: $viewModel.editingModel.detail.newKillphrase,
                    lockState: $viewModel.editingModel.detail.lockState,
                )
            }
            .formStyle(.grouped)
            Divider()
            VaultMacEditorButtons(
                canSave: viewModel.editingModel
                    .isValid && (viewModel.isInitialCreation || viewModel.editingModel.isDirty),
                isSaving: viewModel.isSaving,
                deleteConfirmation: viewModel.isInitialCreation
                    ? nil
                    : (viewModel.strings.deleteConfirmTitle, viewModel.strings.deleteConfirmSubtitle),
                cancel: close,
                save: {
                    await viewModel.saveChanges()
                    // A new item's editor closes once it's created, and an existing one's once its changes are saved.
                    if !viewModel.isInitialCreation, !viewModel.editingModel.isDirty {
                        close()
                    }
                },
                delete: { await viewModel.delete() },
            )
        }
        .frame(width: 520, height: 620)
        .onReceive(viewModel.isFinishedPublisher()) { close() }
        .vaultMacEditorErrorAlert(viewModel.didEncounterErrorPublisher())
        .sheet(isPresented: $isScanning) {
            scanner
        }
    }

    private var keySection: some View {
        Section {
            HStack {
                Button("Scan QR Code…") { isScanning = true }
                Button("Choose Image…") {
                    Task { await readImage() }
                }
            }
            if let scanProblem {
                Text(scanProblem)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("editor.scan-problem")
            }
            Picker("Type", selection: $viewModel.editingModel.detail.codeType) {
                Text("Time-Based").tag(OTPAuthType.Kind.totp)
                Text("Counter-Based").tag(OTPAuthType.Kind.hotp)
            }
            VaultMacTextField(
                "Secret Key",
                text: $viewModel.editingModel.detail.secretBase32String,
                isMonospaced: true,
                identifier: "editor.secret",
            )
            switch viewModel.editingModel.detail.codeType {
            case .totp:
                Stepper(
                    "Period: \(viewModel.editingModel.detail.totpPeriodLength) seconds",
                    value: $viewModel.editingModel.detail.totpPeriodLength,
                    in: 1 ... 3600,
                )
            case .hotp:
                Stepper(
                    "Counter: \(viewModel.editingModel.detail.hotpCounterValue)",
                    value: $viewModel.editingModel.detail.hotpCounterValue,
                    in: 0 ... UInt64(Int64.max),
                )
            }
            Picker("Algorithm", selection: $viewModel.editingModel.detail.algorithm) {
                ForEach(OTPAuthAlgorithm.allCases, id: \.self) { algorithm in
                    Text(Self.name(of: algorithm)).tag(algorithm)
                }
            }
            Picker("Digits", selection: $viewModel.editingModel.detail.numberOfDigits) {
                ForEach([6, 7, 8] as [UInt16], id: \.self) { digits in
                    Text("\(digits)").tag(digits)
                }
            }
        } header: {
            Text("Code")
        }
    }

    private var scanner: some View {
        VStack(spacing: 12) {
            Text("Hold the QR code up to the camera.")
                .font(.headline)
            VaultMacQRCodeScanner { text in
                apply(scanned: text)
            } didFail: { failure in
                scanProblem = failure.message
                isScanning = false
            }
            .frame(width: 480, height: 360)
            .clipShape(.rect(cornerRadius: 8))
            Button("Cancel", role: .cancel) { isScanning = false }
                .keyboardShortcut(.cancelAction)
        }
        .padding()
    }

    private func readImage() async {
        guard let codes = await VaultMacQRCodeImageReader.chooseImage() else { return }
        guard let text = codes.first else {
            scanProblem = "There's no QR code in that image."
            return
        }
        apply(scanned: text)
    }

    private static func name(of algorithm: OTPAuthAlgorithm) -> String {
        switch algorithm {
        case .sha1: "SHA-1"
        case .sha256: "SHA-256"
        case .sha512: "SHA-512"
        }
    }

    /// Fills the key in from a scanned code, once it's checked (G77).
    private func apply(scanned text: String) {
        if let code = Self.code(scanned: text) {
            viewModel.applyScannedCode(code)
            scanProblem = nil
            isScanning = false
        } else {
            scanProblem = "That QR code isn't a code Vault can use."
        }
    }

    /// The code in a scanned QR code, checked as the iOS app checks it (G77), or `nil` if it isn't one Vault can use.
    static func code(scanned text: String) -> OTPAuthCode? {
        guard case let .endScanning(.dataRetrieved(code)) = OTPCodeScanningHandler().decode(data: text) else {
            return nil
        }
        return code
    }
}
