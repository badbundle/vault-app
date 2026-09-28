import Foundation
import SwiftUI
import VaultFeed

/// Shown instead of the vault when the on-disk store could not be opened,
/// replacing what was previously a hard crash at launch.
///
/// Deliberately static: no retry that could write to the broken store, no
/// destructive "start fresh" action (that needs its own design — see
/// MANIFESTO C6), and no diagnostics upload (C3). The one exception is a
/// vault whose data is missing altogether (`.vaultMissing`): there's nothing
/// left to break, and erasing is the only way to start again, so it's offered,
/// and runs only once the user confirms.
struct VaultStoreFailureView: View {
    /// Why the vault couldn't be opened.
    enum Reason: Equatable {
        /// The store couldn't be opened, or how the vault is stored couldn't be worked out.
        case storeUnreadable
        /// The App Lock Password is off, and the device key that opens the vault isn't in this device's keychain:
        /// for example, after a backup that isn't encrypted was restored onto another iPhone.
        case deviceKeyMissing
        /// The vault's data isn't on the device at all, and nothing shows it was erased on purpose: for example, a
        /// restore brought back its settings without it.
        case vaultMissing
    }

    var reason: Reason = .storeUnreadable
    let message: String?
    /// Erases and starts again, for `.vaultMissing`.
    var missingVault: MissingVaultViewModel?

    @State private var isConfirmingErase = false

    var body: some View {
        Form {
            Section {
                PlaceholderView(
                    systemIcon: systemIcon,
                    title: "Vault Unavailable",
                    subtitle: subtitle,
                )
                .padding()
                .containerRelativeFrame(.horizontal)
                .foregroundStyle(.red)
            }

            Section {
                switch reason {
                case .storeUnreadable:
                    Text(
                        "Your data was not deleted. Files Vault couldn't open are kept on this device, some moved aside next to the store, so they can be recovered later.",
                    )
                    Text(
                        "Quit and relaunch the app to try again. If this keeps happening, restore a backup of your iPhone that includes Vault's data, or get in touch through Vault's page on the App Store. Keep Vault installed meanwhile: deleting the app deletes its data.",
                    )
                case .deviceKeyMissing:
                    Text(
                        "Your vault was not deleted. With the App Lock Password off, it's opened by a key kept in this device's keychain, and a backup restored onto another iPhone only brings that key with it if the backup is encrypted, or from iCloud.",
                    )
                    Text(
                        "Restore an encrypted or iCloud backup of your iPhone to get the key back, or get in touch through Vault's page on the App Store. Keep Vault installed meanwhile: deleting the app deletes your vault.",
                    )
                case .vaultMissing:
                    Text(
                        "Nothing has been deleted. Vault's settings say your vault is encrypted on this device, but its data isn't here. Restoring a backup, or moving to a new iPhone, can leave it behind.",
                    )
                    Text(
                        "Restore a backup of your iPhone that includes Vault's data. Otherwise, erase and start again with an empty vault, then restore from a backup PDF.",
                    )
                }
            } header: {
                Text("What Now")
            }

            if reason == .vaultMissing, let missingVault {
                eraseSection(missingVault)
            }

            if let message {
                Section {
                    Text(message)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Details")
                }
            }
        }
    }

    /// Erases and starts again, once the user has confirmed it: it deletes Vault's keys and settings on this device,
    /// and can't be undone.
    private func eraseSection(_ missingVault: MissingVaultViewModel) -> some View {
        Section {
            Button(role: .destructive) {
                isConfirmingErase = true
            } label: {
                ProminentActionLabel(
                    "Erase and Start Again",
                    systemImage: "trash.fill",
                    isLoading: missingVault.state == .erasing,
                )
            }
            .prominentActionButton()
            .disabled(missingVault.state == .erasing)
            .confirmationDialog("Erase and Start Again?", isPresented: $isConfirmingErase, titleVisibility: .visible) {
                Button("Erase and Start Again", role: .destructive) {
                    Task { await missingVault.eraseAndStartAgain() }
                }
            } message: {
                Text(
                    "Vault's keys and settings on this device are deleted, and it starts again with an empty vault. This can't be undone.",
                )
            }
        } footer: {
            if missingVault.state == .failed {
                Text("It couldn't finish erasing. Try again, or open Vault again later.")
            } else {
                Text("Only do this if you can't restore the vault.")
            }
        }
    }

    private var systemIcon: String {
        switch reason {
        case .storeUnreadable: "externaldrive.trianglebadge.exclamationmark"
        case .deviceKeyMissing: "key.slash"
        case .vaultMissing: "questionmark.folder"
        }
    }

    private var subtitle: String {
        switch reason {
        case .storeUnreadable: "The vault's data store could not be opened."
        case .deviceKeyMissing: "The key that opens the vault isn't on this device."
        case .vaultMissing: "The vault's data isn't on this device."
        }
    }
}
