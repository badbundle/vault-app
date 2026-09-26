import Foundation
import SwiftUI
import VaultFeed

/// A new code's first step: scan its QR code, or enter its key.
///
/// A scan fills in the key and the names, and moves on to naming the code.
struct OTPCodeKeyStep: View {
    var viewModel: OTPCodeDetailViewModel
    @Environment(VaultInjector.self) private var injector

    var body: some View {
        OTPCodeKeySections(viewModel: viewModel, intervalTimer: injector.intervalTimer)
    }
}

private struct OTPCodeKeySections: View {
    @Bindable var viewModel: OTPCodeDetailViewModel
    @State private var scanner: CodeScanningManager<OTPCodeScanningHandler>
    @State private var isImagePickerVisible = false

    init(viewModel: OTPCodeDetailViewModel, intervalTimer: any IntervalTimer) {
        self.viewModel = viewModel
        _scanner = State(initialValue: CodeScanningManager(
            intervalTimer: intervalTimer,
            handler: OTPCodeScanningHandler(),
        ))
    }

    private var strings: OTPCodeDetailViewModel.Strings {
        viewModel.strings
    }

    var body: some View {
        Section {
            CodeScanningView(scanner: scanner, isImagePickerVisible: $isImagePickerVisible)
                .frame(maxWidth: .infinity)

            Button {
                isImagePickerVisible = true
            } label: {
                FormRow(image: Image(systemName: "photo.on.rectangle"), color: .accentColor, style: .standard) {
                    Text("Choose a QR Code Image")
                }
            }
        } header: {
            Text("Scan")
        }
        .onAppear {
            scanner.startScanning()
        }
        .onDisappear {
            scanner.disable()
        }
        .onReceive(scanner.itemScannedPublisher()) { code in
            viewModel.applyScannedCode(code)
        }

        Section {
            LabeledTextField(
                strings.inputSecretTitle,
                text: $viewModel.editingModel.detail.secretBase32String,
                status: keyStatus,
            )
            .fontDesign(.monospaced)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.characters)

            Picker(selection: $viewModel.editingModel.detail.codeType) {
                ForEach(OTPAuthType.Kind.allCases) { authType in
                    Text(strings.codeKindTitle(kind: authType))
                        .tag(authType)
                }
            } label: {
                Text(strings.inputCodeTypeTitle)
            }

            DisclosureGroup {
                advancedOptions
            } label: {
                Text(strings.advancedSectionTitle)
            }
        } header: {
            Text("Or Enter the Key")
        } footer: {
            Text("The setup key is usually shown next to the QR code, as a string of letters and numbers.")
        }
    }

    @ViewBuilder
    private var advancedOptions: some View {
        switch viewModel.editingModel.detail.codeType {
        case .totp:
            Stepper(value: $viewModel.editingModel.detail.totpPeriodLength, in: 1 ... UInt64(Int.max)) {
                LabeledContent(strings.inputTotpPeriodTitle, value: "\(viewModel.editingModel.detail.totpPeriodLength)")
            }
        case .hotp:
            Stepper(value: $viewModel.editingModel.detail.hotpCounterValue, in: 0 ... UInt64(Int.max)) {
                LabeledContent(
                    strings.inputHotpCounterTitle,
                    value: "\(viewModel.editingModel.detail.hotpCounterValue)",
                )
            }
        }

        Picker(selection: $viewModel.editingModel.detail.algorithm) {
            ForEach(OTPAuthAlgorithm.allCases) { algorithm in
                Text(algorithm.stringValue)
                    .tag(algorithm)
            }
        } label: {
            Text(strings.inputAlgorithmTitle)
        }

        Stepper(value: $viewModel.editingModel.detail.numberOfDigits, in: 1 ... UInt16.max) {
            LabeledContent(strings.inputNumberOfDigitsTitle, value: "\(viewModel.editingModel.detail.numberOfDigits)")
        }
    }

    private var keyStatus: LabeledTextField.Status {
        switch viewModel.editingModel.detail.$secretBase32String {
        case .valid: .valid()
        case .invalid: .none
        case let .error(message): .error(message: message ?? strings.inputKeyErrorTitle)
        }
    }
}

/// What the code is called: the site and account, and an optional description.
struct OTPCodeNameStep: View {
    @Bindable var viewModel: OTPCodeDetailViewModel

    var body: some View {
        let strings = viewModel.strings
        Section {
            LabeledTextField(
                strings.siteNameTitle,
                text: $viewModel.editingModel.detail.issuerTitle,
                status: .init(errorFrom: viewModel.editingModel.detail.$issuerTitle),
            )

            LabeledTextField(
                strings.accountNameTitle,
                text: $viewModel.editingModel.detail.accountNameTitle,
                prompt: strings.accountNameExample,
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }

        Section {
            LabeledTextField(
                strings.descriptionTitle,
                text: $viewModel.editingModel.detail.description,
                prompt: strings.descriptionSubtitle,
                kind: .multiline(minLines: 3),
            )
        } footer: {
            Text("Optional. Shown with the code, and searchable.")
        }
    }
}

/// Who can see the code, and how it's protected.
struct OTPCodeSecurityStep: View {
    @Bindable var viewModel: OTPCodeDetailViewModel

    var body: some View {
        let detail = viewModel.editingModel.detail
        DetailEditorVisibilitySection(
            viewConfig: $viewModel.editingModel.detail.viewConfig,
            passphrase: $viewModel.editingModel.detail.searchPassphrase,
            passphraseValidation: detail.$searchPassphrase,
            hasExistingPassphrase: detail.hasExistingSearchPassphrase,
            explanation: "A hidden code stays out of the feed. It only appears when you search for its passphrase exactly.",
            hiddenWarning: viewModel.strings.passphraseSubtitle,
        )

        Section {
            Toggle(isOn: $viewModel.editingModel.detail.showInQuickType) {
                FormRow(image: Image(systemName: "keyboard"), color: .accentColor, style: .standard) {
                    Text("Show in QuickType")
                }
            }
        } footer: {
            Text("Offers the code above the keyboard when a site asks for it.")
        }

        DetailEditorLockSection(
            lockState: $viewModel.editingModel.detail.lockState,
            explanation: "A locked code needs Face ID, Touch ID or your passcode every time you view or copy it.",
        )

        DetailEditorKillphraseSection(
            isEnabled: $viewModel.editingModel.detail.killphraseEnabled,
            newKillphrase: $viewModel.editingModel.detail.newKillphrase,
            isValid: detail.isKillphraseValid,
            hasExistingKillphrase: viewModel.editingModel.initialDetail.killphraseEnabled,
            explanation: "A killphrase deletes this code, immediately and quietly, when you search for it exactly. With a passphrase too, the code can be deleted without it ever being shown.",
            enabledWarning: viewModel.strings.killphraseSubtitle,
        )
    }
}
