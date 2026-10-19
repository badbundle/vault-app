import SwiftUI
import VaultCore
import VaultFeed

/// A private key's page: what it's recognized as, and the key, masked until clicked. It hides again while Vault isn't
/// the active app, and can't be copied or selected, as a recovery phrase's words can't (G105).
struct VaultMacPrivateKeyDetailView: View {
    var privateKey: PrivateKey
    var metadata: VaultItem.Metadata
    var tags: [VaultItemTag]
    /// The key it was decrypted with: a private key is always encrypted.
    var encryptionKey: DerivedEncryptionKey

    @State private var isKeyRevealed = false
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Text(privateKey.title.isBlank ? "Private Key" : privateKey.title)
                    .font(.largeTitle.bold())
                Spacer()
                VaultMacItemPageButtons(
                    request: .editPrivateKey(privateKey, metadata, encryptionKey),
                    metadata: metadata,
                )
            }
            if privateKey.contents.isNotEmpty {
                Text(privateKey.contents)
            }
            VaultMacPrivateKeyValidationLabel(
                summary: PrivateKeyValidationSummary(validation: PrivateKeyValidator.validate(privateKey.key)),
            )
            key
            VaultMacDetailFooter(metadata: metadata, tags: tags)
        }
        .onChange(of: appearsActive) { _, isActive in
            if !isActive {
                isKeyRevealed = false
            }
        }
    }

    private var isShowingKey: Bool {
        isKeyRevealed && appearsActive
    }

    private var key: some View {
        Button {
            isKeyRevealed.toggle()
        } label: {
            VaultMacMaskedPrivateKey(key: privateKey.key, isRevealed: isShowingKey)
        }
        .buttonStyle(.plain)
        .help(isShowingKey ? "Hide Key" : "Show Key")
        .accessibilityLabel(isShowingKey ? "Hide key" : "Show key")
        .accessibilityIdentifier("detail.private-key")
    }
}

/// A private key, or a mask the same length for every key, in a box. Its text can't be selected.
struct VaultMacMaskedPrivateKey: View {
    var key: String
    var isRevealed: Bool

    var body: some View {
        Text(verbatim: isRevealed ? PrivateKey.displayText(for: key) : String(repeating: "•", count: 20))
            .font(.body.monospaced())
            .foregroundStyle(isRevealed ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.quinary, in: .rect(cornerRadius: 12))
            .contentShape(.rect(cornerRadius: 12))
    }
}

/// What a private key is recognized as, and whether it's valid.
struct VaultMacPrivateKeyValidationLabel: View {
    var summary: PrivateKeyValidationSummary

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.title)
                    .fontWeight(.semibold)
                Text(summary.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: summary.systemIconName)
                .foregroundStyle(iconColor)
        }
        .accessibilityElement(children: .combine)
    }

    private var iconColor: Color {
        switch summary.kind {
        case .valid: .green
        case .warning: .orange
        case .neutral: .secondary
        }
    }
}
