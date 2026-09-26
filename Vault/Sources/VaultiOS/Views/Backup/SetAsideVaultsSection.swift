import Foundation
import SwiftUI
import VaultFeed

/// Says, on the Backups page, that the vault couldn't be opened and was set aside, and deletes what was set
/// aside when the user asks. Shows nothing if nothing was set aside.
struct SetAsideVaultsSection: View {
    @State private var viewModel: SetAsideVaultsViewModel
    @State private var isConfirmingDelete = false

    init(viewModel: SetAsideVaultsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        if let summary = viewModel.summary {
            Section {
                FormRow(image: Image(systemName: "externaldrive.fill.badge.exclamationmark"), color: .orange) {
                    TextAndSubtitle(title: isPlural ? "Vaults Set Aside" : "Vault Set Aside", subtitle: summary)
                }
                .accessibilityElement(children: .combine)

                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Text(isPlural ? "Delete Set-Aside Vaults" : "Delete Set-Aside Vault")
                }
                .disabled(viewModel.isDeleting)
                .confirmationDialog(
                    isPlural ? "Delete the set-aside vaults?" : "Delete the set-aside vault?",
                    isPresented: $isConfirmingDelete,
                    titleVisibility: .visible,
                ) {
                    Button("Delete", role: .destructive) {
                        Task { await viewModel.deleteAll() }
                    }
                } message: {
                    Text("Any items in it that aren't in a backup will be gone for good.")
                }
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        "The set-aside files stay on this device, unencrypted, and the app can't open them. Restore your items from a backup, then delete them.",
                    )
                    if let error = viewModel.deleteError {
                        Text(error.userDescription ?? error.userTitle)
                            .foregroundStyle(.red)
                    }
                }
            }
            .onAppear {
                // Deleting all data elsewhere removes them too.
                viewModel.reload()
            }
        }
    }

    private var isPlural: Bool {
        viewModel.archives.count > 1
    }
}
