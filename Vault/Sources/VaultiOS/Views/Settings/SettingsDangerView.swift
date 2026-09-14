import Foundation
import SwiftUI
import Toasts
import VaultFeed

struct SettingsDangerView: View {
    private var viewModel: SettingsDangerViewModel
    @State private var deleteError: PresentationError?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.presentToast) private var presentToast

    init(viewModel: SettingsDangerViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        Form {
            headerSection
            deleteAllSection
        }
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(viewModel.isDeleting)
    }

    private var headerSection: some View {
        Section {
            PlaceholderView(
                systemIcon: "exclamationmark.triangle.fill",
                title: "Danger Zone",
                subtitle: "Be careful what you do here.",
            )
            .padding()
            .containerRelativeFrame(.horizontal)
            .foregroundStyle(.red)
        }
    }

    private var deleteAllSection: some View {
        Section {
            AsyncButton {
                do {
                    withAnimation {
                        deleteError = nil
                    }
                    try await viewModel.deleteEntireVault()
                    let deletedToast = ToastValue(icon: Image(systemName: "checkmark"), message: "Vault Deleted")
                    presentToast(deletedToast)
                    dismiss()
                } catch let error as PresentationError {
                    withAnimation {
                        deleteError = error
                    }
                }
            } label: {
                deleteAllRow {
                    Text("Delete All Data")
                        .foregroundStyle(Color.red)
                }
            } loading: {
                deleteAllRow {
                    ProgressView()
                }
            }
        } footer: {
            if let deleteError {
                Text(deleteError.userDescription ?? "Error deleting data.")
                    .foregroundStyle(.red)
            }
        }
    }

    private func deleteAllRow(@ViewBuilder content: @escaping () -> some View) -> some View {
        FormRow(image: Image(systemName: "trash.fill"), color: .red, content: content)
    }
}
