import Foundation
import Testing

/// No sheet, full-screen cover or popover is chained onto a list `Section`.
///
/// A `Section` applies its modifiers to each of its parts: its rows, and its header and footer if it has them. For
/// these presentations that makes one presenter per part, all sharing the same binding, and on the first tap they
/// cancel each other out so nothing appears. That's why the item editor's Tags, Encryption and Password rows needed a
/// second tap. Chain the presentation onto the row that opens it instead.
struct SectionPresentationTests {
    /// The presentations that break when a section repeats them. An alert, confirmation dialog or file importer on a
    /// section still shows on the first tap.
    static let presentationModifiers: Set = ["sheet", "fullScreenCover", "popover"]

    @Test
    func noSectionHasAPresentationChainedOntoIt() throws {
        let sections = try ViewCallScanner.callsInAppSources(to: ["Section"])

        let presenting = sections.filter { !Self.presentationModifiers.isDisjoint(with: $0.call.modifiers) }
        #expect(
            presenting.isEmpty,
            """
            Chain sheets, full-screen covers and popovers onto the row that opens them, not its Section: a section \
            repeats them for its header and footer, and the copies stop the first tap presenting anything. On:
            \(presenting.map(\.description).joined(separator: "\n"))
            """,
        )
    }

    /// Guards against the check passing because it found nothing to check.
    @Test
    func findsTheSectionsInTheAppSources() throws {
        let sections = try ViewCallScanner.callsInAppSources(to: ["Section"])

        #expect(sections.contains { $0.file == "DetailEditorAppearanceStep.swift" })
        #expect(sections.contains { $0.file == "DetailEditorSecuritySections.swift" })
        // As well as the sections, the modifiers chained onto them.
        let editorSections = sections.filter { $0.file == "DetailEditorView.swift" }
        #expect(editorSections.contains { $0.call.modifiers.contains("listRowInsets") })
    }
}

// MARK: - Scanner

extension SectionPresentationTests {
    @Test
    func scanner_findsModifiersAfterASectionsHeaderAndFooter() {
        let calls = ViewCallScanner.calls(to: ["Section"], in: """
        Section {
            Button("Tags") {
                isShowingTags = true
            }
        } header: {
            Text("Tags")
        } footer: {
            Text("Tags group items together.")
        }
        .sheet(isPresented: $isShowingTags) {
            TagPicker()
        }
        """)

        #expect(calls == [.init(name: "Section", line: 1, modifiers: ["sheet"])])
    }

    @Test
    func scanner_findsASectionWithATitle() {
        let calls = ViewCallScanner.calls(to: ["Section"], in: """
        Section("Tags") {
            Text("Work")
        }
        .popover(isPresented: $isShowingTags) {
            TagPicker()
        }
        """)

        #expect(calls == [.init(name: "Section", line: 1, modifiers: ["popover"])])
    }

    @Test
    func scanner_findsModifiersOnARowSeparately() {
        let calls = ViewCallScanner.calls(to: ["Section", "Button"], in: """
        Section {
            Button("Tags") {
                isShowingTags = true
            }
            .sheet(isPresented: $isShowingTags) {
                TagPicker()
            }
        } footer: {
            Text("Tags group items together.")
        }
        """)

        #expect(calls == [
            .init(name: "Section", line: 1, modifiers: []),
            .init(name: "Button", line: 2, modifiers: ["sheet"]),
        ])
    }

    @Test
    func scanner_skipsDeclarations() {
        let calls = ViewCallScanner.calls(to: ["Section"], in: """
        extension Section {
            func tagged() -> some View {
                self
            }
        }
        """)

        #expect(calls.isEmpty)
    }
}
