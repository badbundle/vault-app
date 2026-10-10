import SwiftUI
import VaultCore
import VaultFeed
import VaultSettings

/// One item in the list: what it is, and for a code, its live code, which copies it when clicked.
///
/// A row says no more about an item than its tile in the iOS feed does: a note can hide its title, a locked code shows
/// dots, and nothing marks an item that has a killphrase or a search passphrase (C5).
struct VaultMacItemRow: View {
    var item: VaultItem
    var showsNextCode: Bool
    /// Clicking the code copies it, rather than only opening its page (Tap a Code To).
    var copiesOnClick: Bool

    @Environment(\.vaultMacItemPreviews) private var previews
    @Environment(\.vaultMacCopy) private var copy
    @State private var didCopy = false

    var body: some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if let subtitle, subtitle.isNotEmpty {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let code = previews?.code(for: item) {
                codeButton(code)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("feed.item")
    }

    private var icon: some View {
        Image(systemName: iconName)
            .font(.title3)
            .foregroundStyle(color)
            .frame(width: 24)
            .accessibilityHidden(true)
    }

    private var color: Color {
        let color = item.metadata.color ?? .default
        return Color(red: color.red, green: color.green, blue: color.blue)
    }

    private func codeButton(_ code: OTPCodePreviewViewModel) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .trailing, spacing: 0) {
                if showsNextCode, let next = code.nextCode {
                    Text(VaultMacOTPCodeText.grouped(next))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if copiesOnClick {
                    Button {
                        Task { await copyCode(code) }
                    } label: {
                        VaultMacOTPCodeText(state: code.code, font: .title3)
                    }
                    .buttonStyle(.plain)
                    .help("Copy Code")
                    .accessibilityIdentifier("feed.item.code")
                } else {
                    VaultMacOTPCodeText(state: code.code, font: .title3)
                        .accessibilityIdentifier("feed.item.code")
                }
            }
            if let timer = previews?.timer(for: item) {
                VaultMacCodeTimer(state: timer)
            }
        }
        .overlay(alignment: .trailing) {
            if didCopy {
                Text("Copied")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.thinMaterial, in: .capsule)
                    .transition(.opacity)
            }
        }
        .animation(.snappy, value: didCopy)
    }

    private func copyCode(_ code: OTPCodePreviewViewModel) async {
        guard let action = code.pasteboardCopyText, let copy, await copy(action) else { return }
        didCopy = true
        try? await Task.sleep(for: .seconds(1.5))
        didCopy = false
    }

    private var iconName: String {
        switch item.item {
        case .otpCode: item.metadata.lockState.isLocked ? "lock.fill" : "key.horizontal.fill"
        case .secureNote: item.metadata.lockState.isLocked ? "lock.doc.fill" : "doc.text.fill"
        case .encryptedItem, .recoveryPhrase: "lock.shield.fill"
        }
    }

    private var title: String {
        switch item.item {
        case let .otpCode(code):
            code.data.issuer.isBlank ? "Unnamed Code" : code.data.issuer
        case let .secureNote(note):
            SecureNotePreviewViewModel(
                title: note.title,
                description: item.metadata.userDescription,
                color: item.metadata.color ?? .default,
                isLocked: item.metadata.lockState.isLocked,
                textFormat: note.format,
                previewMode: item.metadata.previewMode,
            ).visibleTitle
        case let .encryptedItem(encrypted):
            EncryptedItemPreviewViewModel(
                title: encrypted.title,
                color: item.metadata.color ?? .default,
                previewMode: item.metadata.previewMode,
            ).visibleTitle
        case .recoveryPhrase:
            // Only ever stored encrypted, so the list never has one decrypted.
            "Untitled Item"
        }
    }

    private var subtitle: String? {
        switch item.item {
        case let .otpCode(code):
            item.metadata.lockState.isLocked ? nil : code.data.accountName
        case .secureNote:
            item.metadata.lockState.isLocked || item.metadata.previewMode != .titleAndFirstLine
                ? nil
                : item.metadata.userDescription
        case .encryptedItem, .recoveryPhrase:
            "Encrypted"
        }
    }
}

/// Gives every row in a list of items the height of the tallest one: a title with a subtitle, or a code with its next
/// code above it.
///
/// The Mac's list measures the rows it has when it first shows them, but not a row it inserts later, such as an item
/// that's just been added. It gives that row its default height of 24 points, which clips it until something makes the
/// list lay out again (VAULT-124). With every row at least this tall, an inserted row has its full height from the
/// start.
struct VaultMacItemRowHeight: ViewModifier {
    /// A row with a subtitle at the default text size, with the row's padding and the list's.
    @ScaledMetric(relativeTo: .body) private var height = 49.0

    func body(content: Content) -> some View {
        content.environment(\.defaultMinListRowHeight, height)
    }
}

extension View {
    /// Every row in this list of items is as tall as the tallest one (`VaultMacItemRowHeight`).
    func vaultMacItemRowHeight() -> some View {
        modifier(VaultMacItemRowHeight())
    }
}
