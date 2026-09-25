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
    /// `nil` when the item must stay encrypted, in which case the password can be changed but not removed.
    var didRemoveEncryption: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var doPasswordsMatch: Bool {
        newEncryptionPassword == newEncryptionPasswordConfirm
    }

    /// For an item where encryption is optional, so can be removed once enabled.
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

    /// For an item that must always be encrypted. There's no way to remove the encryption, only to set or change
    /// the password.
    init(
        title: String,
        description: String,
        hasExistingPassword: Bool,
        didSetNewEncryptionPassword: @escaping (String) -> Void,
    ) {
        self.title = title
        self.description = description
        _encryptionIsEnabled = State(initialValue: hasExistingPassword)
        self.didSetNewEncryptionPassword = didSetNewEncryptionPassword
        didRemoveEncryption = nil
    }

    var body: some View {
        Form {
            titleSection
            switch (encryptionIsEnabled, didRemoveEncryption) {
            case let (true, .some(didRemoveEncryption)):
                removeEncryptionSection(didRemoveEncryption: didRemoveEncryption)
            case (true, nil):
                changePasswordSection
            case (false, .some):
                passwordEntrySection(actionTitle: "Encrypt", systemImage: "lock.fill")
            case (false, nil):
                passwordEntrySection(actionTitle: "Set Password", systemImage: "lock.fill")
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

    @ViewBuilder
    private func passwordEntrySection(actionTitle: String, systemImage: String) -> some View {
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
        }

        if newEncryptionPassword.isNotBlank {
            Section {
                ProminentActionButton(actionTitle, systemImage: systemImage) {
                    didSetNewEncryptionPassword(newEncryptionPassword)
                    dismiss()
                }
                .disabled(!doPasswordsMatch)
            }
        }
    }

    @ViewBuilder
    private var changePasswordSection: some View {
        Section {
            Text("""
            This item is always encrypted. \
            After changing the password, the old password no longer works for this item, \
            but backups made before the change still need the old password. \
            A forgotten password can't be recovered.
            """)
            .foregroundStyle(.secondary)
            .font(.caption)
        }

        passwordEntrySection(actionTitle: "Change Password", systemImage: "key.fill")
    }

    @ViewBuilder
    private func removeEncryptionSection(didRemoveEncryption: @escaping () -> Void) -> some View {
        Section {
            Text("""
            Encryption is currently enabled for this item. \
            This means the data, on your device, is cryptographically inaccessible without your password. \
            The stronger your password, the stronger the encryption.
            """)
            .foregroundStyle(.secondary)
            .font(.caption)
        }

        Section {
            ProminentActionButton("Remove Encryption", systemImage: "lock.slash.fill", role: .destructive) {
                didRemoveEncryption()
                dismiss()
            }
        }
    }
}
