import Foundation
import Testing
@testable import VaultiOS

/// Markdown in the app never loads an image.
///
/// MarkdownUI's default image providers fetch an image's URL over the network, so every `Markdown` view in the app's
/// sources has to chain `.markdownImagesNeverLoad()` onto its declaration.
struct MarkdownImagesNeverLoadTests {
    @Test
    func everyMarkdownViewNeverLoadsImages() throws {
        let calls = try ViewCallScanner.callsInAppSources(to: ["Markdown"])

        let undeclared = calls.filter { !$0.call.modifiers.contains("markdownImagesNeverLoad") }
        #expect(
            undeclared.isEmpty,
            """
            Chain .markdownImagesNeverLoad() onto every Markdown view, so an image in it never goes online. Missing on:
            \(undeclared.map(\.description).joined(separator: "\n"))
            """,
        )
    }

    /// Guards against the check passing because it found nothing to check.
    @Test
    func findsTheMarkdownViewsInTheAppSources() throws {
        let calls = try ViewCallScanner.callsInAppSources(to: ["Markdown"])

        #expect(calls.contains { $0.file == "SecureNoteDetailView.swift" })
        #expect(calls.contains { $0.file == "LiteratureView.swift" })
    }

    @Test
    func inlineImages_areNeverLoaded() async throws {
        let sut = NeverLoadedMarkdownImageProvider()

        await #expect(throws: NeverLoadedMarkdownImageProvider.NotLoaded.self) {
            _ = try await sut.image(with: #require(URL(string: "https://example.com/image.png")), label: "Image")
        }
    }
}
