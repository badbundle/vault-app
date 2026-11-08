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
        if viewModel.state.isOpened {
            VaultMacBackupNotice(
                systemImage: "checkmark.circle.fill",
                title: "This Backup Opens",
                message: "Its password is right, and everything in it can be restored. Nothing on this Mac was changed.",
                action: ("Check Another Backup…", choose),
            )
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
