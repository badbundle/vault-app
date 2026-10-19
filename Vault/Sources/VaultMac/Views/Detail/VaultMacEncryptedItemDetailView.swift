import SwiftUI
import VaultCore
import VaultFeed

/// An item encrypted with a password of its own: a note, a recovery phrase or a private key. It opens once its password
/// is entered, and the password is never stored (G42).
struct VaultMacEncryptedItemDetailView: View {
    @State var viewModel: EncryptedItemDetailViewModel
    var tags: [VaultItemTag]
    var authentication: DeviceAuthenticationService

    var body: some View {
        switch viewModel.state {
        case let .decrypted(payload, key):
            VaultMacAuthenticationGate(
                isRequired: Self.requiresDeviceAuthentication(payload),
                reason: Self.authenticationReason(payload),
                authentication: authentication,
                locksWhenInactive: true,
            ) {
                decrypted(payload, key: key)
            }
        default:
            passwordForm
                #if DEBUG
                .task { await VaultMacScreenshotMode.openEncryptedItem(viewModel) }
                #endif
        }
    }

    /// Whether what's decrypted also needs Touch ID or the Mac's password before it shows. A recovery phrase or a
    /// private key always does, whatever its stored lock state: its password protects it from someone coercing the
    /// user, and Touch ID or the Mac's password from someone at an unattended Mac (G41, G105). A note needs them only
    /// when its item is locked, which its page has already asked for.
    nonisolated static func requiresDeviceAuthentication(_ payload: VaultItem.Payload) -> Bool {
        switch payload {
        case .recoveryPhrase, .privateKey: true
        case .secureNote, .otpCode, .encryptedItem: false
        }
    }

    /// What the Touch ID prompt says it's for.
    nonisolated static func authenticationReason(_ payload: VaultItem.Payload) -> String {
        switch payload {
        case .privateKey: "Show the private key"
        case .recoveryPhrase, .secureNote, .otpCode, .encryptedItem: "Show the recovery phrase"
        }
    }

    @ViewBuilder
    private func decrypted(_ payload: VaultItem.Payload, key: DerivedEncryptionKey) -> some View {
        switch payload {
        case let .secureNote(note):
            VaultMacNoteDetailView(note: note, metadata: viewModel.metadata, tags: tags, encryptionKey: key)
        case let .recoveryPhrase(phrase):
            VaultMacRecoveryPhraseDetailView(
                phrase: phrase,
                metadata: viewModel.metadata,
                tags: tags,
                encryptionKey: key,
            )
        case let .privateKey(privateKey):
            VaultMacPrivateKeyDetailView(
                privateKey: privateKey,
                metadata: viewModel.metadata,
                tags: tags,
                encryptionKey: key,
            )
        case .otpCode, .encryptedItem:
            // Only notes, recovery phrases and private keys are encrypted with a password of their own.
            EmptyView()
        }
    }

    private var passwordForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(viewModel.item.title.isBlank ? "Untitled Item" : viewModel.item.title)
                .font(.largeTitle.bold())
            Text("This item is encrypted with a password of its own.")
                .foregroundStyle(.secondary)
            HStack {
                SecureField("Password", text: $viewModel.enteredEncryptionPassword)
                    .secretTextInput()
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await viewModel.startDecryption() } }
                    .accessibilityIdentifier("detail.encryption-password")
                Button("Open") {
                    Task { await viewModel.startDecryption() }
                }
                .disabled(!viewModel.canStartDecryption)
                .keyboardShortcut(.defaultAction)
            }
            .disabled(viewModel.isLoading)
            .frame(maxWidth: 360)
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
            if let error = viewModel.state.presentationError {
                Text(error.userDescription ?? error.userTitle)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("detail.decryption-error")
            }
        }
    }
}

/// A recovery phrase's words, numbered, masked until clicked. They hide again while Vault isn't the active app, and
/// can't be copied or selected (G41).
struct VaultMacRecoveryPhraseDetailView: View {
    var phrase: RecoveryPhrase
    var metadata: VaultItem.Metadata
    var tags: [VaultItemTag]
    /// The key it was decrypted with: a recovery phrase is always encrypted.
    var encryptionKey: DerivedEncryptionKey

    @State private var areWordsRevealed = false
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Text(phrase.title.isBlank ? "Recovery Phrase" : phrase.title)
                    .font(.largeTitle.bold())
                Spacer()
                VaultMacItemPageButtons(
                    request: .editRecoveryPhrase(phrase, metadata, encryptionKey),
                    metadata: metadata,
                )
            }
            if phrase.contents.isNotEmpty {
                Text(phrase.contents)
            }
            words
            if phrase.passphrase.isNotEmpty {
                VaultMacDetailField(title: "Passphrase") {
                    Text(isShowingWords ? phrase.passphrase : String(repeating: "•", count: 8))
                        .font(.body.monospaced())
                }
            }
            VaultMacDetailFooter(metadata: metadata, tags: tags)
        }
        .onChange(of: appearsActive) { _, isActive in
            if !isActive {
                areWordsRevealed = false
            }
        }
    }

    private var isShowingWords: Bool {
        areWordsRevealed && appearsActive
    }

    private var words: some View {
        Button {
            areWordsRevealed.toggle()
        } label: {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), spacing: 10) {
                ForEach(Array(phrase.words.enumerated()), id: \.offset) { index, word in
                    HStack(spacing: 6) {
                        Text("\(index + 1).")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Text(isShowingWords ? word : "••••••")
                            .font(.body.monospaced())
                    }
                }
            }
            .padding(16)
            .background(.quinary, in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .help(isShowingWords ? "Hide Words" : "Show Words")
        .accessibilityLabel(isShowingWords ? "Hide words" : "Show words")
        .accessibilityIdentifier("detail.recovery-words")
    }
}
