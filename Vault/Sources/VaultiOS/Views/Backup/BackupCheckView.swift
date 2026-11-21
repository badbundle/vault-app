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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(viewModel: BackupCheckViewModel) {
        _viewModel = .init(wrappedValue: viewModel)
    }

    private enum Modal: IdentifiableSelf {
        case enterPassword(EncryptedVault)
        case cameraScanning
    }

    var body: some View {
        Form {
            if case let .opened(checked) = viewModel.state {
                openedHeaderSection(checked)
                howCheckedSection(checked)
            } else {
                headerSection
            }
            sourcesSection
        }
        .navigationTitle(Text("Check a Backup"))
        .navigationBarTitleDisplayMode(.inline)
        .animation(.snappy, value: viewModel.state)
        .sensoryFeedback(.success, trigger: viewModel.state) { _, newValue in
            newValue.isOpened
        }
        .asksForRating(after: viewModel.state.isOpened)
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

    /// What the check does, or why the backup couldn't be read, in the same place.
    private var headerSection: some View {
        BackupImportHeaderSection(
            title: "Check a Backup",
            subtitle: "Make sure a backup opens with its password, without restoring it. Nothing on this device changes.",
            systemImage: "doc.text.magnifyingglass",
            color: .accentColor,
            error: error,
        )
    }

    /// The backup opened: its seal is stamped in, to match against the one printed on its PDF.
    private func openedHeaderSection(_ checked: BackupCheckViewModel.CheckedBackup) -> some View {
        Section {
            BackupHeroHeader(
                title: "This Backup Opens",
                subtitle: "Its password is right, and everything in it can be restored. Nothing on this device was changed.",
                icon: .seal(checked.seal),
                iconSize: 56,
                bouncesOnAppear: true,
            ) {
                BackupSealLabel(seal: checked.seal)
            }
            // A new check stamps the seal again.
            .id(checked.id)
        }
    }

    // MARK: - How Checked Section

    /// What opening the backup proved, one step at a time, as the password screen did it. It says how the backup is
    /// protected, which anyone with its file can read, and nothing about what it holds.
    private func howCheckedSection(_ checked: BackupCheckViewModel.CheckedBackup) -> some View {
        Section {
            ForEach(Array(Self.steps(for: checked).enumerated()), id: \.offset) { index, step in
                FormRow(image: Image(systemName: step.systemImage), color: .green) {
                    TextAndSubtitle(title: step.title, subtitle: step.detail)
                }
                .accessibilityElement(children: .combine)
                // Each step comes in after the one before, once the seal has been stamped.
                .transition(
                    reduceMotion
                        ? .opacity
                        : .asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 12))
                                .animation(.snappy.delay(0.4 + Double(index) * 0.25)),
                            removal: .opacity,
                        ),
                )
            }
        } header: {
            Text("How Vault Checked It")
        } footer: {
            Text("Encrypted backup format \(checked.formatVersion).")
        }
    }

    private struct Step {
        var systemImage: String
        var title: String
        var detail: String
    }

    private static func steps(for checked: BackupCheckViewModel.CheckedBackup) -> [Step] {
        [
            Step(
                systemImage: "key.horizontal.fill",
                title: "Key Made From Its Password",
                detail: checked.keyDerivation.map { "\($0), slow on purpose, so guessing is slow too." }
                    ?? "Slow on purpose, so guessing is slow too.",
            ),
            Step(
                systemImage: "checkmark.seal.fill",
                title: "Unchanged Since It Was Made",
                detail: "AES-256-GCM checked every byte against the backup's authentication tag.",
            ),
            Step(
                systemImage: "square.stack.3d.up.fill",
                title: "Everything in It Can Be Restored",
                detail: "It decoded in full, as a restore would. Vault kept none of it.",
            ),
        ]
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
            FormActionRow(
                "Choose a PDF Backup",
                subtitle: "A PDF backup or an auto-backup, from Files.",
                systemImage: "doc.text.fill",
                color: .accentColor,
                kind: .disclosure,
                actionOptions: [],
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

            FormActionRow(
                "Scan QR Codes",
                subtitle: "From a printed PDF backup.",
                systemImage: "qrcode.viewfinder",
                color: .indigo,
                kind: .disclosure,
                actionOptions: [],
            ) {
                viewModel.clearResult()
                modal = .cameraScanning
            }
        } footer: {
            Text("The backup is opened only to check it, then forgotten. Nothing in it is added to your vault.")
        }
    }
}
