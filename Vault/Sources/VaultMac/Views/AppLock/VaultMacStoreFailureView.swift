import SwiftUI
import VaultFeed

/// Shown instead of the vault when Vault couldn't open its storage at launch. It never deletes anything that might be
/// the only copy of a vault (G80), and says to keep Vault installed.
struct VaultMacStoreFailureView: View {
    var failure: VaultMacStoreFailure
    var missingVault: MissingVaultViewModel?

    @State private var isConfirmingErase = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.lock.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text("Vault Couldn't Open")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            if let missingVault {
                // Erasing can't be undone, and deletes the keys killphrases and search passphrases are checked with,
                // so it asks first, as on iOS.
                Button("Erase and Start Again…", role: .destructive) {
                    isConfirmingErase = true
                }
                .controlSize(.large)
                .disabled(missingVault.state == .erasing || missingVault.state == .erased)
                .accessibilityIdentifier("store-failure.erase")
                .confirmationDialog("Erase Vault?", isPresented: $isConfirmingErase) {
                    Button("Erase", role: .destructive) {
                        Task { await missingVault.eraseAndStartAgain() }
                    }
                } message: {
                    Text(
                        "Everything Vault keeps on this Mac is erased, and it starts again as on its first launch. This can't be undone. Restore a backup afterwards to bring your items back.",
                    )
                }
                if missingVault.state == .erasing {
                    ProgressView()
                        .controlSize(.small)
                } else if missingVault.state == .failed {
                    Text("Vault couldn't erase everything. Try again.")
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("store-failure")
    }

    private var message: String {
        switch failure {
        case .storeUnreadable:
            "Vault's data couldn't be read. Keep Vault installed, and try opening it again later."
        case .vaultMissing:
            "Vault's data is missing. If you have a backup, you can erase Vault and restore it."
        case .deviceKeyMissing:
            "The key that opens Vault on this Mac is missing. Keep Vault installed, and try opening it again later."
        }
    }
}
