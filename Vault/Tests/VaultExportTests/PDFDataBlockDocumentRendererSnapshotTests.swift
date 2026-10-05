// The Mac renders PDFs from VAULT-104.
#if canImport(UIKit)
import ImageTools
import PDFKit
import TestHelpers
import Testing
import VaultExport

@MainActor
struct PDFDataBlockDocumentRendererSnapshotTests {
    @Test
    func render_drawsEmptyPDFDocument() throws {
        let sut = makeSUT(tilesPerRow: 3)
        let pdf = try sut.render(document: emptyDocument())

        assertSnapshot(of: pdf, as: .pdf())
    }

    @Test
    func render_drawsSingleImage() throws {
        let sut = makeSUT(tilesPerRow: 3)
        let document = DataBlockDocument(content: [.dataBlock([anyData()])])
        let pdf = try sut.render(document: document)

        assertSnapshot(of: pdf, as: .pdf())
    }

    @Test
    func render_drawsRowOfImages() throws {
        let sut = makeSUT(tilesPerRow: 3)
        let document = DataBlockDocument(content: [.dataBlock(Array(repeating: anyData(), count: 3))])
        let pdf = try sut.render(document: document)

        assertSnapshot(of: pdf, as: .pdf())
    }

    @Test
    func render_drawsLabelsOfDifferentStyles() throws {
        let sut = makeSUT(tilesPerRow: 10)
        let document = DataBlockDocument(content: [
            .title(.init(
                text: "Test 1",
                font: .systemFont(ofSize: 18, weight: .bold),
                textColor: .red,
                padding: .zero,
            )),
            .title(.init(
                text: "Test 2",
                font: .systemFont(ofSize: 24, weight: .regular),
                textColor: .darkGray,
                padding: .zero,
            )),
            .title(.init(
                text: "Test 3",
                font: .systemFont(ofSize: 12, weight: .heavy),
                textColor: .lightGray,
                padding: .zero,
            )),
            .title(.init(
                text: "Test 4",
                font: .systemFont(ofSize: 34, weight: .thin),
                textColor: .systemBlue,
                padding: .zero,
            )),
        ])
        let pdf = try sut.render(document: document)

        assertSnapshot(of: pdf, as: .pdf())
    }

    @Test
    func render_drawsIntersposedImagesAndTitles() throws {
        let sut = makeSUT(tilesPerRow: 10)
        let document = DataBlockDocument(content: [
            .dataBlock(Array(repeating: anyData(), count: 10)),
            .title(longSubtitle(padding: .zero)),
            .dataBlock(Array(repeating: anyData(), count: 3)),
            .title(longSubtitle(padding: .zero)),
            .dataBlock(Array(repeating: anyData(), count: 2)),
            .title(longSubtitle(padding: .zero)),
        ])
        let pdf = try sut.render(document: document)

        assertSnapshot(of: pdf, as: .pdf())
    }

    @Test
    func render_drawsLabelsOnNextPageIfNotEnoughRoom() throws {
        let sut = makeSUT(tilesPerRow: 10)
        let document = DataBlockDocument(content: [
            .dataBlock(Array(repeating: anyData(), count: 10)),
            .title(longSubtitle(padding: .zero)),
            .dataBlock(Array(repeating: anyData(), count: 3)),
            .title(longSubtitle(padding: .zero)),
            .dataBlock(Array(repeating: anyData(), count: 2)),
            .title(longSubtitle(padding: .zero)),
            .title(longSubtitle(padding: .zero)),
            .title(longSubtitle(padding: .zero)),
            .title(longSubtitle(padding: .zero)),
            .title(longSubtitle(padding: .zero)),
            .title(longSubtitle(padding: .zero)),
            .title(longSubtitle(padding: .zero)),
            .title(longSubtitle(padding: .zero)),
        ])
        let pdf = try sut.render(document: document)

        assertSnapshot(of: pdf, as: .pdf(page: 1), named: "page1")
        assertSnapshot(of: pdf, as: .pdf(page: 2), named: "page2")
    }

    @Test
    func render_drawsGridRowOfImagesWith10TilesPerRow() throws {
        let sut = makeSUT(tilesPerRow: 10)
        let document = DataBlockDocument(content: [.dataBlock(Array(repeating: anyData(), count: 24))])
        let pdf = try sut.render(document: document)

        assertSnapshot(of: pdf, as: .pdf())
    }

    @Test
    func render_drawsMultiplePagesOfImages() throws {
        let sut = makeSUT(tilesPerRow: 3)
        let document = DataBlockDocument(content: [.dataBlock(Array(repeating: anyData(), count: 14))])
        let pdf = try sut.render(document: document)

        assertSnapshot(of: pdf, as: .pdf(page: 1), named: "page1")
        assertSnapshot(of: pdf, as: .pdf(page: 2), named: "page2")
    }

    @Test
    func render_ignoresOffsetForTitleOnSecondPage() throws {
        let sut = makeSUT(tilesPerRow: 3)
        let titleLabel = DataBlockLabel(
            text: "Hello World",
            font: UIFont.systemFont(ofSize: 50, weight: .bold),
            padding: .init(top: 36, left: 10, bottom: 22, right: 10),
        )
        let document = DataBlockDocument(
            content: [
                .title(titleLabel),
                .dataBlock(Array(repeating: anyData(), count: 14)),
            ],
        )
        let pdf = try sut.render(document: document)

        assertSnapshot(of: pdf, as: .pdf(page: 1), named: "page1")
        assertSnapshot(of: pdf, as: .pdf(page: 2), named: "page2")
    }

    @Test
    func render_drawsTitleAboveImages() throws {
        let sut = makeSUT(tilesPerRow: 10)
        let titleLabel = DataBlockLabel(
            text: "Hello World",
            font: UIFont.systemFont(ofSize: 50, weight: .bold),
            padding: .init(top: 36, left: 10, bottom: 22, right: 10),
        )
        let document = DataBlockDocument(
            content: [
                .title(titleLabel),
                .dataBlock(Array(repeating: anyData(), count: 14)),
            ],
        )
        let pdf = try sut.render(document: document)

        assertSnapshot(of: pdf, as: .pdf())
    }

    @Test
    func render_drawsLongTitleAboveImages() throws {
        let sut = makeSUT(tilesPerRow: 10)
        let title = Array(repeating: "Title", count: 10).joined(separator: " ")
        let titleLabel = DataBlockLabel(
            text: "<START> \(title) <END>",
            font: UIFont.systemFont(ofSize: 50, weight: .bold),
            padding: .init(top: 36, left: 10, bottom: 22, right: 10),
        )
        let document = DataBlockDocument(
            content: [
                .title(titleLabel),
                .dataBlock(Array(repeating: anyData(), count: 14)),
            ],
        )
        let pdf = try sut.render(document: document)

        assertSnapshot(of: pdf, as: .pdf())
    }

    @Test
    func render_drawsSubtitleAboveImages() throws {
        let sut = makeSUT(tilesPerRow: 10)
        let subtitleMain = Array(repeating: "Subtitle", count: 50).joined(separator: " ")
        let titleLabel = DataBlockLabel(
            text: "<START> \(subtitleMain) <END>",
            font: UIFont.systemFont(ofSize: 14, weight: .regular),
            padding: .init(top: 36, left: 10, bottom: 22, right: 10),
        )
        let document = DataBlockDocument(
            content: [
                .title(titleLabel),
                .dataBlock(Array(repeating: anyData(), count: 14)),
            ],
        )
        let pdf = try sut.render(document: document)

        assertSnapshot(of: pdf, as: .pdf())
    }

    @Test
    func render_drawsTitleAndSubtitleAboveImages() throws {
        let sut = makeSUT(tilesPerRow: 10)
        let titleLabel = DataBlockLabel(
            text: "Hello World",
            font: UIFont.systemFont(ofSize: 50, weight: .bold),
            padding: .init(top: 36, left: 10, bottom: 0, right: 10),
        )
        let document = DataBlockDocument(
            content: [
                .title(titleLabel),
                .title(longSubtitle()),
                .dataBlock(Array(repeating: anyData(), count: 14)),
            ],
        )
        let pdf = try sut.render(document: document)

        assertSnapshot(of: pdf, as: .pdf())
    }

    @Test
    func render_respectsPageNoMargin() throws {
        let sut = makeSUT(tilesPerRow: 4, documentSize: NoMarginsDocumentSize())
        let text = Array(repeating: "Hello", count: 30).joined(separator: " ")
        let label = DataBlockLabel(text: text, font: .systemFont(ofSize: 13), padding: .zero)
        let document = DataBlockDocument(
            content: [
                .title(label),
                .dataBlock(Array(repeating: anyData(), count: 14)),
            ],
        )
        let pdf = try sut.render(document: document)

        assertSnapshot(of: pdf, as: .pdf(page: 1))
    }

    @Test
    func render_repectsPageOffCenterMargins() throws {
        let sut = makeSUT(tilesPerRow: 4, documentSize: OffCenterMarginsDocumentSize())
        let text = Array(repeating: "Hello", count: 30).joined(separator: " ")
        let label = DataBlockLabel(text: text, font: .systemFont(ofSize: 13), padding: .zero)
        let document = DataBlockDocument(
            content: [
                .title(label),
                .dataBlock(Array(repeating: anyData(), count: 14)),
            ],
        )
        let pdf = try sut.render(document: document)

        assertSnapshot(of: pdf, as: .pdf(page: 1))
    }

    @Test
    func render_labelsRespectPadding() throws {
        let sut = makeSUT(tilesPerRow: 10)
        let title = longTitle(padding: .init(top: 40, left: 40, bottom: 10, right: 40))
        let subtitle = longSubtitle(padding: .init(top: 40, left: 60, bottom: 10, right: 60))
        let document = DataBlockDocument(
            content: [
                .title(title),
                .title(subtitle),
                .dataBlock(Array(repeating: anyData(), count: 0)),
            ],
        )
        let pdf = try sut.render(document: document)

        assertSnapshot(of: pdf, as: .pdf())
    }

    @Test
    func render_drawsShortHeaders() throws {
        let pdf = try makeDocumentWithHeaderGenerator(headerGenerator: ShortHeaderGenerator())

        assertSnapshot(of: pdf, as: .pdf())
    }

    @Test
    func render_drawsLongHeaders() throws {
        let pdf = try makeDocumentWithHeaderGenerator(headerGenerator: LongHeaderGenerator())

        assertSnapshot(of: pdf, as: .pdf())
    }

    @Test
    func render_drawsLeftHeadersOnly() throws {
        let pdf = try makeDocumentWithHeaderGenerator(headerGenerator: LeftHeaderGenerator())

        assertSnapshot(of: pdf, as: .pdf())
    }

    @Test
    func render_drawsRightHeadersOnly() throws {
        let pdf = try makeDocumentWithHeaderGenerator(headerGenerator: RightHeaderGenerator())

        assertSnapshot(of: pdf, as: .pdf())
    }

    @Test
    func render_drawsHeadersOnAllPages() throws {
        let pdf = try makeDocumentWithHeaderGenerator(headerGenerator: PageNumberHeaderGenerator(), numberOfImages: 50)

        assertSnapshot(of: pdf, as: .pdf(page: 1))
        assertSnapshot(of: pdf, as: .pdf(page: 2))
    }

    // MARK: - Helpers

    private func makeSUT(
        tilesPerRow: UInt,
        documentSize: any PDFDocumentSize = USLetterDocumentSize(),
        imageRenderer: RGBCyclingStubColorImageRenderer = RGBCyclingStubColorImageRenderer(),
    ) -> some PDFDocumentRenderer<DataBlockDocument> {
        PDFDataBlockDocumentRenderer(
            documentSize: documentSize,
            rendererFactory: StubPDFRendererFactory(),
            imageRenderer: imageRenderer,
            blockLayout: { size in
                VerticalTilingDataBlockLayout(bounds: size, tilesPerRow: tilesPerRow, spacing: 5)
            },
        )
    }

    private func anyData() -> Data {
        Data(repeating: 0xFF, count: 10)
    }

    private func emptyDocument() -> DataBlockDocument {
        DataBlockDocument(content: [])
    }

    private func longTitle(padding: UIEdgeInsets = .init(top: 36, left: 10, bottom: 0, right: 10)) -> DataBlockLabel {
        let title = Array(repeating: "Title", count: 10).joined(separator: " ")
        return DataBlockLabel(
            text: "<START> \(title) <END>",
            font: UIFont.systemFont(ofSize: 50, weight: .bold),
            padding: padding,
        )
    }

    private func longSubtitle(padding: UIEdgeInsets = .init(top: 12, left: 10, bottom: 14, right: 10))
        -> DataBlockLabel
    {
        let subtitleMain = Array(repeating: "Subtitle", count: 50).joined(separator: " ")
        return DataBlockLabel(
            text: "<START> \(subtitleMain) <END>",
            font: UIFont.systemFont(ofSize: 14, weight: .regular),
            padding: padding,
        )
    }

    private func makeDocumentWithHeaderGenerator(
        headerGenerator: any DataBlockHeaderGenerator,
        numberOfImages: Int = 10,
    ) throws -> PDFDocument {
        let sut = PDFDataBlockDocumentRenderer(
            documentSize: USLetterDocumentSize(),
            rendererFactory: StubPDFRendererFactory(),
            imageRenderer: PlainBlackColorImageRenderer(),
            blockLayout: { size in
                VerticalTilingDataBlockLayout(bounds: size, tilesPerRow: 5, spacing: 5)
            },
        )
        let title = DataBlockLabel(
            text: "My Title",
            font: UIFont.systemFont(ofSize: 50, weight: .bold),
            padding: .zero,
        )
        let subtitle = DataBlockLabel(
            text: "Testing headers only - no padding on these labels",
            font: UIFont.systemFont(ofSize: 18, weight: .regular),
            padding: .zero,
        )
        let document = DataBlockDocument(
            headerGenerator: headerGenerator,
            content: [
                .title(title),
                .title(subtitle),
                .dataBlock(Array(repeating: anyData(), count: numberOfImages)),
            ],
        )
        return try sut.render(document: document)
    }
}

private struct NoMarginsDocumentSize: PDFDocumentSize {
    var inchDimensions: (width: Double, height: Double) {
        USLegalDocumentSize().inchDimensions
    }

    var inchMargins: Margins {
        .all(0)
    }
}

private struct OffCenterMarginsDocumentSize: PDFDocumentSize {
    var inchDimensions: (width: Double, height: Double) {
        USLegalDocumentSize().inchDimensions
    }

    var inchMargins: Margins {
        .init(top: 0, left: 0, bottom: 2, right: 2)
    }
}

private struct StubPDFRendererFactory: PDFRendererFactory {
    /// us letter size for stub
    var size: any PDFDocumentSize = USLetterDocumentSize()
}

private class RGBCyclingStubColorImageRenderer: ImageDataRenderer {
    var states: [UIColor] = [.red, .green, .blue]
    var currentState = 0
    func makeImage(fromData _: Data) -> UIImage? {
        defer { currentState += 1 }
        return UIImage.from(color: states[currentState % states.count])
    }
}

private class PlainBlackColorImageRenderer: ImageDataRenderer {
    func makeImage(fromData _: Data) -> UIImage? {
        UIImage.from(color: .black)
    }
}

private class ShortHeaderGenerator: DataBlockHeaderGenerator {
    func makeHeader(pageNumber _: Int) -> DataBlockHeader? {
        DataBlockHeader(left: "LEFT", right: "RIGHT")
    }
}

private class LongHeaderGenerator: DataBlockHeaderGenerator {
    func makeHeader(pageNumber _: Int) -> DataBlockHeader? {
        let left = Array(repeating: "LEFT", count: 100).joined(separator: " ")
        let right = Array(repeating: "RIGHT", count: 100).joined(separator: " ")
        return DataBlockHeader(left: left, right: right)
    }
}

private class LeftHeaderGenerator: DataBlockHeaderGenerator {
    func makeHeader(pageNumber _: Int) -> DataBlockHeader? {
        let left = Array(repeating: "LEFT", count: 100).joined(separator: " ")
        return DataBlockHeader(left: left, right: nil)
    }
}

private class RightHeaderGenerator: DataBlockHeaderGenerator {
    func makeHeader(pageNumber _: Int) -> DataBlockHeader? {
        let right = Array(repeating: "RIGHT", count: 100).joined(separator: " ")
        return DataBlockHeader(left: nil, right: right)
    }
}

private class PageNumberHeaderGenerator: DataBlockHeaderGenerator {
    func makeHeader(pageNumber: Int) -> DataBlockHeader? {
        DataBlockHeader(left: "L: Page \(pageNumber)", right: "R: Page \(pageNumber)")
    }
}
#endif
