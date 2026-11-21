import Combine
import SwiftUI
import VaultBackup
import VaultFeed
import VaultMacShared

/// Check a Backup: that a backup PDF opens with its password, without restoring it (G106). It reads neither the vault
/// nor the backup key and changes nothing, so unlike Restore it doesn't ask for Touch ID or the Mac's password first.
struct VaultMacCheckPage: View {
    var services: VaultMacBackupServices
    @State var viewModel = BackupCheckViewModel()
    /// Chooses a PDF, as the Open panel does unless a test says otherwise.
    var choosePDF: @MainActor () -> URL? = { VaultMacImportSheet.runPDFPanel(prompt: "Check") }

    @State private var decryptedVaults = PassthroughSubject<VaultApplicationPayload, Never>()
    @State private var decryptor: BackupKeyDecryptorViewModel?

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The backup opened. What it held is dropped here: the check only says that it opened.
            .onReceive(decryptedVaults) { _ in
                decryptor = nil
                viewModel.backupDidOpen()
            }
            .onChange(of: viewModel.state) { _, state in
                if case let .needsPasswordEntry(vault) = state {
                    decryptor = BackupKeyDecryptorViewModel(
                        encryptedVault: vault,
                        keyDeriverFactory: services.keyDeriverFactory,
                        encryptedVaultDecoder: services.encryptedVaultDecoder,
                        decryptedVaultSubject: decryptedVaults,
                    )
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if case let .opened(checked) = viewModel.state {
            opened(checked)
                .accessibilityIdentifier("backups.check.opened")
        } else if let decryptor {
            VaultMacBackupDecryptView(viewModel: decryptor) {
                self.decryptor = nil
                viewModel.cancelPasswordEntry()
            }
        } else {
            sources
        }
    }

    /// The backup opened: its seal, stamped in, then what opening it proved, as on iOS.
    private func opened(_ checked: BackupCheckViewModel.CheckedBackup) -> some View {
        VStack(spacing: 14) {
            BackupSealView(seal: checked.seal, stampsOnAppear: true)
                .frame(width: 96)
                .id(checked.id)
            Text("This Backup Opens")
                .font(.title2.bold())
            Text("Its password is right, and everything in it can be restored. Nothing on this Mac was changed.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Text(verbatim: "Seal \(checked.seal.code)")
                .font(.body.monospaced().weight(.semibold))
                .accessibilityLabel(Text("Backup Seal"))
                .accessibilityValue(Text(checked.seal.spokenCode))
            VStack(alignment: .leading, spacing: 10) {
                checkedStep(
                    "key.horizontal.fill",
                    "Key made from its password",
                    checked.keyDerivation.map { "\($0), slow on purpose, so guessing is slow too." }
                        ?? "Slow on purpose, so guessing is slow too.",
                )
                checkedStep(
                    "checkmark.seal.fill",
                    "Unchanged since it was made",
                    "AES-256-GCM checked every byte against its authentication tag.",
                )
                checkedStep(
                    "square.stack.3d.up.fill",
                    "Everything in it can be restored",
                    "It decoded in full, as a restore would. Vault kept none of it.",
                )
            }
            .frame(maxWidth: 380, alignment: .leading)
            .padding(.top, 4)
            Button("Check Another Backup…", action: choose)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("backups.notice-action")
                .padding(.top, 4)
        }
        .padding(28)
    }

    private func checkedStep(_ systemImage: String, _ title: String, _ detail: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.green)
        }
        .accessibilityElement(children: .combine)
    }

    private var sources: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Check a Backup")
                .font(.title2.bold())
            Text(
                "Make sure a backup opens with its password, without restoring it. The backup is opened only to check it, then forgotten.",
            )
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 380)
            Button("Choose PDF…") { choose() }
                .accessibilityIdentifier("backups.check.choose-pdf")
                .controlSize(.large)
            if case let .error(error) = viewModel.state {
                Text(error.userDescription ?? error.userTitle)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("backups.check.error")
            }
        }
        .padding(28)
    }

    private func choose() {
        viewModel.clearResult()
        guard let url = choosePDF() else { return }
        Task {
            await viewModel.check(pdf: VaultMacImportSheet.read(url))
        }
    }
}
