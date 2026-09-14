import Combine
import Foundation
import SwiftUI
import VaultFeed

struct EncryptedItemDetailView: View {
    @State private var viewModel: EncryptedItemDetailViewModel
    /// Signaled when the given `VaultItem` should be opened in place of this detail view.
    var openDetailSubject: PassthroughSubject<VaultItemEncryptionPayload, Never>
    /// Required to know the presentation context, so we know how this view should be dismissed.
    var presentationMode: Binding<PresentationMode>?

    init(
        viewModel: EncryptedItemDetailViewModel,
        openDetailSubject: PassthroughSubject<VaultItemEncryptionPayload, Never>,
        presentationMode: Binding<PresentationMode>? = nil,
    ) {
        self.viewModel = viewModel
        self.openDetailSubject = openDetailSubject
        self.presentationMode = presentationMode
    }

    private func dismiss() {
        presentationMode?.wrappedValue.dismiss()
    }

    var body: some View {
        Form {
            titleSection
            passwordEntrySection
        }
        .navigationTitle("Item")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(viewModel.isLoading)
        .onChange(of: viewModel.state) { _, newValue in
            switch newValue {
            case let .decrypted(item, encryptionKey):
                // An item was just decrypted, open it.
                // Create a quasi-item that uses the metadata of the encrypted item, but with the contents
                // of the note.
                let quasiItem = VaultItem(metadata: viewModel.metadata, item: item)
                let payload = VaultItemEncryptionPayload(decryptedItem: quasiItem, encryptionKey: encryptionKey)
                openDetailSubject.send(payload)
            default:
                break
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
                .disabled(viewModel.isLoading)
            }
        }
    }

    private var titleSection: some View {
        Section {
            if let error = viewModel.state.presentationError {
                PlaceholderView(
                    systemIcon: "exclamationmark.triangle.fill",
                    title: error.userTitle,
                    subtitle: error.userDescription,
                )
                .padding()
                .containerRelativeFrame(.horizontal)
                .foregroundStyle(.red)
            } else {
                PlaceholderView(
                    systemIcon: "lock.iphone",
                    title: "Encrypted",
                    subtitle: "A password is required to decrypt this item.",
                )
                .padding()
                .containerRelativeFrame(.horizontal)
            }
        }
    }

    private var passwordEntrySection: some View {
        Section {
            FormRow(image: Image(systemName: "lock.fill"), color: .primary, style: .standard) {
                SecureField("Password...", text: $viewModel.enteredEncryptionPassword)
            }
        } footer: {
            AsyncButton {
                await viewModel.startDecryption()
            } label: {
                Label("Decrypt", systemImage: "key.horizontal.fill")
            } loading: {
                ProgressView()
                    .tint(.white)
            }
            .modifier(ProminentButtonModifier())
            .animation(.easeOut, value: viewModel.state)
            .padding()
            .frame(maxWidth: .infinity)
            .disabled(!viewModel.canStartDecryption)
        }
        .onChange(of: viewModel.enteredEncryptionPassword) { _, _ in
            // When the text changes, reset the state.
            viewModel.resetState()
        }
    }
}
