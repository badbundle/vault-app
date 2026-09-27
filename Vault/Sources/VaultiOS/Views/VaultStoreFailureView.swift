import Foundation
import SwiftUI

/// Shown instead of the vault when the on-disk store could not be opened,
/// replacing what was previously a hard crash at launch.
///
/// Deliberately static: no retry that could write to the broken store, no
/// destructive "start fresh" action (that needs its own design — see
/// MANIFESTO C6), and no diagnostics upload (C3).
struct VaultStoreFailureView: View {
    /// Why the vault couldn't be opened.
    enum Reason: Equatable {
        /// The store couldn't be opened, or how the vault is stored couldn't be worked out.
        case storeUnreadable
        /// The App Lock Password is off, and the device key that opens the vault isn't in this device's keychain:
        /// for example, after a backup that isn't encrypted was restored onto another iPhone.
        case deviceKeyMissing
    }

    var reason: Reason = .storeUnreadable
    let message: String?

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
                        "Your data was not deleted. The unreadable store files were moved aside, next to the store, so they can be inspected or recovered later.",
                    )
                    Text(
                        "Quit and relaunch the app to try again. If this keeps happening, reinstall the app and restore from a backup PDF.",
                    )
                case .deviceKeyMissing:
                    Text(
                        "Your vault was not deleted. With the App Lock Password off, it's opened by a key kept in this device's keychain, and a backup restored onto another iPhone only brings that key with it if the backup is encrypted, or from iCloud.",
                    )
                    Text(
                        "Restore an encrypted or iCloud backup of your iPhone to get the key back. Otherwise, reinstall the app and restore from a backup PDF.",
                    )
                }
            } header: {
                Text("What Now")
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

    private var systemIcon: String {
        switch reason {
        case .storeUnreadable: "externaldrive.trianglebadge.exclamationmark"
        case .deviceKeyMissing: "key.slash"
        }
    }

    private var subtitle: String {
        switch reason {
        case .storeUnreadable: "The vault's data store could not be opened."
        case .deviceKeyMissing: "The key that opens the vault isn't on this device."
        }
    }
}
