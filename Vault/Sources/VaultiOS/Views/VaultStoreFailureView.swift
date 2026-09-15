import Foundation
import SwiftUI

/// Shown instead of the vault when the on-disk store could not be opened,
/// replacing what was previously a hard crash at launch.
///
/// Deliberately static: no retry that could write to the broken store, no
/// destructive "start fresh" action (that needs its own design — see
/// MANIFESTO C6), and no diagnostics upload (C3).
struct VaultStoreFailureView: View {
    let message: String?

    var body: some View {
        Form {
            Section {
                PlaceholderView(
                    systemIcon: "externaldrive.trianglebadge.exclamationmark",
                    title: "Vault Unavailable",
                    subtitle: "The vault's data store could not be opened.",
                )
                .padding()
                .containerRelativeFrame(.horizontal)
                .foregroundStyle(.red)
            }

            Section {
                Text(
                    "Your data was not deleted. The unreadable store files were moved aside, next to the store, so they can be inspected or recovered later.",
                )
                Text(
                    "Quit and relaunch the app to try again. If this keeps happening, reinstall the app and restore from a backup PDF.",
                )
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
}
