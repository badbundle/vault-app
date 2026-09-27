import Foundation
import SwiftUI
import VaultFeed

/// Shown instead of the vault while an erase the app was stopped in the middle of finishes, and if it can't.
///
/// Until the erase is done nothing may read the vault, so there's nothing else to show. It says no more about what
/// went wrong than that it didn't finish (MANIFESTO C3).
struct InterruptedEraseView: View {
    var viewModel: InterruptedEraseViewModel

    var body: some View {
        switch viewModel.state {
        case .erasing, .erased:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            Form {
                Section {
                    BackupHeroHeader(
                        title: "Erase Not Finished",
                        subtitle: "Vault was erasing its data when it stopped, and couldn't finish. Nothing can be opened until it does.",
                        // The erase's own symbol, as in the settings that turn it on and the Danger Zone.
                        systemImage: "trash.fill",
                        color: .red,
                        iconSize: 56,
                    )
                }

                Section {
                    ProminentActionButton("Try Again", systemImage: "arrow.clockwise", actionOptions: []) {
                        await viewModel.finish()
                    }
                } footer: {
                    Text("If it still can't finish, open Vault again later.")
                }
            }
        }
    }
}
