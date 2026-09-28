import Foundation
import MarkdownUI
import SwiftUI

extension View {
    /// Markdown here never loads an image.
    ///
    /// MarkdownUI's default image providers fetch an image's URL over the network, so a note containing
    /// `![](https://…)` would contact that server every time it's opened. Vault never goes online, so an image in
    /// Markdown shows nothing instead.
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
