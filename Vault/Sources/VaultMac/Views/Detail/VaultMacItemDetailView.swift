import SwiftUI
import VaultCore
import VaultFeed

/// An item's page: the same content as on iOS.
///
/// A locked item shows nothing of itself until Touch ID or the Mac's password has passed, and locks again when another
/// item is opened or Vault locks (G32).
struct VaultMacItemDetailView: View {
    var item: VaultItem
    var tags: [VaultItemTag]
    var authentication: DeviceAuthenticationService
    var keyDeriverFactory: any VaultKeyDeriverFactory

    var body: some View {
        VaultMacAuthenticationGate(
            isRequired: item.metadata.lockState.isLocked,
            reason: "Show the item",
            authentication: authentication,
        ) {
            ScrollView {
                content
                    .frame(maxWidth: 560, alignment: .leading)
                    .padding(28)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityIdentifier("detail")
    }

    @ViewBuilder
    private var content: some View {
        switch item.item {
        case let .otpCode(code):
            VaultMacOTPDetailView(item: item, code: code, tags: tags)
        case let .secureNote(note):
            VaultMacNoteDetailView(note: note, metadata: item.metadata, tags: tags)
        case let .encryptedItem(encrypted):
            VaultMacEncryptedItemDetailView(
                viewModel: EncryptedItemDetailViewModel(
                    item: encrypted,
                    metadata: item.metadata,
                    keyDeriverFactory: keyDeriverFactory,
                ),
                tags: tags,
                authentication: authentication,
            )
            // Made anew once the item is saved, so its page asks for the password again rather than showing what it
            // held before (G42).
            .id(item.metadata.updated)
        case .recoveryPhrase:
            // Only ever stored encrypted: a decrypted one only shows once its encrypted item is opened.
            EmptyView()
        }
    }
}

/// Shows its content only once Touch ID or the Mac's password has passed, when `isRequired`. Until then it shows
/// nothing of what it guards, and it asks again each time it's made, as when another item is opened.
struct VaultMacAuthenticationGate<Content: View>: View {
    var isRequired: Bool
    var reason: String
    var authentication: DeviceAuthenticationService
    /// Asks again once Vault stops being the active app, as a recovery phrase does (G41).
    var locksWhenInactive = false
    @ViewBuilder var content: () -> Content

    @State private var isUnlocked = false
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        Group {
            if isRequired, !isUnlocked {
                lockedNotice
            } else {
                content()
            }
        }
        .onChange(of: appearsActive) { _, isActive in
            if locksWhenInactive, !isActive {
                isUnlocked = false
            }
        }
    }

    private var lockedNotice: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Locked")
                .font(.title2.bold())
            Text("Unlock with Touch ID or your Mac's password to see this item.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Unlock") {
                Task { await unlock() }
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("detail.unlock")
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func unlock() async {
        do {
            try await authentication.validateAuthentication(reason: reason)
            isUnlocked = true
        } catch {
            // It stays locked: the user can try again.
        }
    }
}

/// A heading and its value, as an item's page lists them.
struct VaultMacDetailField<Value: View>: View {
    var title: String
    @ViewBuilder var value: () -> Value

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            value()
        }
    }
}

/// What every page ends with: the item's tags, and when it was made and last changed.
struct VaultMacDetailFooter: View {
    var metadata: VaultItem.Metadata
    var tags: [VaultItemTag]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if tags.isNotEmpty {
                VaultMacDetailField(title: "Tags") {
                    Text(tags.map(\.name).sorted().joined(separator: ", "))
                }
            }
            HStack(spacing: 32) {
                VaultMacDetailField(title: "Created") {
                    Text(metadata.created.formatted(date: .abbreviated, time: .shortened))
                }
                VaultMacDetailField(title: "Updated") {
                    Text(metadata.updated.formatted(date: .abbreviated, time: .shortened))
                }
            }
            .font(.callout)
        }
    }
}
