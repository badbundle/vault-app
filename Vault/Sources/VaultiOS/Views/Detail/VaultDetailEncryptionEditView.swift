import Foundation
import SwiftUI
import VaultFeed

struct VaultDetailEncryptionEditView: View {
    var title: String
    var description: String
    @State private var encryptionIsEnabled: Bool = false

    @State private var newEncryptionPassword = ""
    @State private var newEncryptionPasswordConfirm = ""
    var didSetNewEncryptionPassword: (String) -> Void
    var didRemoveEncryption: () -> Void

    @Environment(\.dismiss) private var dismiss

    var doPasswordsMatch: Bool {
        newEncryptionPassword == newEncryptionPasswordConfirm
    }

    init(
        title: String,
        description: String,
        encryptionInitiallyEnabled: Bool,
        didSetNewEncryptionPassword: @escaping (String) -> Void,
        didRemoveEncryption: @escaping () -> Void,
    ) {
        self.title = title
        self.description = description
        _encryptionIsEnabled = State(initialValue: encryptionInitiallyEnabled)
        self.didSetNewEncryptionPassword = didSetNewEncryptionPassword
        self.didRemoveEncryption = didRemoveEncryption
    }

    var body: some View {
        Form {
            titleSection
            if encryptionIsEnabled {
                removeEncryptionSection
            } else {
                createEncryptionSection
            }
        }
    }

    private var titleSection: some View {
        Section {
            PlaceholderView(systemIcon: "lock.iphone", title: title, subtitle: description)
                .padding()
                .containerRelativeFrame(.horizontal)
        }
    }

    private var createEncryptionSection: some View {
        Section {
            FormRow(image: Image(systemName: "lock.fill"), color: .primary, style: .standard) {
                SecureField("Password...", text: $newEncryptionPassword)
            }

            if newEncryptionPassword.isNotBlank {
                FormRow(
                    image: Image(
                        systemName: doPasswordsMatch ? "checkmark.circle.fill" : "xmark.circle.fill",
                    ),
                    color: doPasswordsMatch ? .green : .red,
                    style: .standard,
                ) {
                    SecureField("Confirm Password", text: $newEncryptionPasswordConfirm)
                }
            }
        } footer: {
            if newEncryptionPassword.isNotBlank {
                Button {
                    didSetNewEncryptionPassword(newEncryptionPassword)
                    dismiss()
                } label: {
                    Label("Encrypt", systemImage: "checkmark.circle.fill")
                }
                .modifier(ProminentButtonModifier())
                .padding()
                .frame(maxWidth: .infinity)
                .disabled(!doPasswordsMatch)
            }
        }
    }

    private var removeEncryptionSection: some View {
        Section {
            Text("""
            Encryption is currently enabled for this item. \
            This means the data, on your device, is cryptographically inaccessible without your password. \
            The stronger your password, the stronger the encryption.
            """)
            .foregroundStyle(.secondary)
            .font(.caption)
        } footer: {
            Button {
                didRemoveEncryption()
                dismiss()
            } label: {
                Label("Remove Encryption", systemImage: "xmark.circle.fill")
            }
            .modifier(ProminentButtonModifier(color: .red))
            .padding()
            .frame(maxWidth: .infinity)
        }
    }
}
