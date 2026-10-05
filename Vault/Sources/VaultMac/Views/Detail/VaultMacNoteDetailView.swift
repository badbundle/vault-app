import MarkdownUI
import SwiftUI
import VaultCore
import VaultFeed

/// A note's page: its title and contents, in Markdown if it's written in it. Images in Markdown are never loaded
/// (G70), and copying goes through Vault's clipboard, not the text (G50).
struct VaultMacNoteDetailView: View {
    var note: SecureNote
    var metadata: VaultItem.Metadata
    var tags: [VaultItemTag]

    @Environment(\.vaultMacCopy) private var copy

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Text(note.title.isBlank ? "Untitled Note" : note.title)
                    .font(.largeTitle.bold())
                Spacer()
                Button("Copy Note") {
                    Task {
                        _ = await copy?(VaultTextCopyAction(
                            text: note.contents,
                            requiresAuthenticationToCopy: false,
                            contentType: .note,
                        ))
                    }
                }
                .disabled(note.contents.isEmpty)
                .accessibilityIdentifier("detail.copy-note")
            }
            contents
                .frame(maxWidth: .infinity, alignment: .leading)
            VaultMacDetailFooter(metadata: metadata, tags: tags)
        }
    }

    @ViewBuilder
    private var contents: some View {
        switch note.format {
        case .markdown:
            Markdown(note.contents)
                .markdownImagesNeverLoad()
        case .plain:
            Text(note.contents)
        }
    }
}

extension View {
    /// Markdown here never loads an image. MarkdownUI's default providers fetch an image's URL over the network, and
    /// Vault never goes online, so an image shows nothing instead (G70).
    func markdownImagesNeverLoad() -> some View {
        markdownImageProvider(NeverLoadedMarkdownImageProvider())
            .markdownInlineImageProvider(NeverLoadedMarkdownImageProvider())
    }
}

/// Stands in for both of MarkdownUI's image providers, and loads nothing.
struct NeverLoadedMarkdownImageProvider: ImageProvider, InlineImageProvider {
    struct NotLoaded: Error {}

    func makeImage(url _: URL?) -> some View {
        EmptyView()
    }

    func image(with _: URL, label _: String) async throws -> Image {
        throw NotLoaded()
    }
}
