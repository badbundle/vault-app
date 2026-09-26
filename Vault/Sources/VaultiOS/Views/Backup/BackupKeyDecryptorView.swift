import Foundation
import SwiftUI
import VaultFeed

/// View for generating an encryption key while decrypting a backup.
@MainActor
struct BackupKeyDecryptorView: View {
    @State private var viewModel: BackupKeyDecryptorViewModel
    @Environment(\.dismiss) private var dismiss

    init(viewModel: BackupKeyDecryptorViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        Form {
            informationSection
            entrySection
            decryptSection
        }
        .navigationTitle(Text("Decrypt Backup"))
        .interactiveDismissDisabled(viewModel.isDecrypting)
        .onChange(of: viewModel.decryptionKeyState) { _, newValue in
            if newValue.isSuccess {
                dismiss()
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                }
                .tint(.red)
                .disabled(viewModel.isDecrypting)
            }
        }
    }

    private var informationSection: some View {
        Section {
            PlaceholderView(
                systemIcon: "lock.document.fill",
                title: viewModel.decryptionKeyState.title,
                subtitle: viewModel.decryptionKeyState.description,
            )
            .padding()
            .containerRelativeFrame(.horizontal)
            .foregroundStyle(viewModel.decryptionKeyState.isError ? .red : .primary)
        }
    }

    private var entrySection: some View {
        Section {
            LabeledTextField(
                "Backup Password",
                text: $viewModel.enteredPassword,
                kind: .secure(),
                status: viewModel.decryptionKeyState.isError ? .error() : .none,
            )
            .secretTextInput(.verbatim)
            .disabled(viewModel.isDecrypting)
        }
    }

    private var decryptSection: some View {
        Section {
            ProminentActionButton("Decrypt", systemImage: "lock.open.fill") {
                await viewModel.attemptDecryption()
            }
            .disabled(!viewModel.canAttemptDecryption || viewModel.isDecrypting)
        }
        .animation(.snappy, value: viewModel.canAttemptDecryption)
    }
}
