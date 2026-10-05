import SwiftUI
import VaultFeed

/// Shown instead of the vault when Vault couldn't open its storage at launch. It never deletes anything that might be
/// the only copy of a vault (G80), and says to keep Vault installed.
struct VaultMacStoreFailureView: View {
    var failure: VaultMacStoreFailure
    var missingVault: MissingVaultViewModel?

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
                Button("Erase and Start Again", role: .destructive) {
                    Task { await missingVault.eraseAndStartAgain() }
                }
                .controlSize(.large)
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
