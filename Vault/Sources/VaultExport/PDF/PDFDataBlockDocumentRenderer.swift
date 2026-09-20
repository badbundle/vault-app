import Foundation
import ImageTools
import PDFKit
import UIKit

public struct PDFDataBlockDocumentRenderer<
    ImageRenderer: ImageDataRenderer,
    RectLayout: RectSeriesLayout & PageLayout,
>: PDFDocumentRenderer {
    public typealias Document = DataBlockDocument

    public let documentSize: any PDFDocumentSize
    public let rendererFactory: any PDFRendererFactory
    public let imageRenderer: ImageRenderer
    public let blockLayout: (CGRect) -> RectLayout

    public init(
        documentSize: any PDFDocumentSize,
        rendererFactory: any PDFRendererFactory,
        imageRenderer: ImageRenderer,
        blockLayout: @escaping (CGRect) -> RectLayout,
    ) {
        self.documentSize = documentSize
        self.rendererFactory = rendererFactory
        self.imageRenderer = imageRenderer
        self.blockLayout = blockLayout
    }

    public func render(document: DataBlockDocument, progress: @escaping (Double) -> Void) throws -> PDFDocument {
        let renderer = rendererFactory.makeRenderer()
        // Images dominate rendering time, so progress is measured in images processed.
        let totalImages = document.totalImageCount
        var processedImages = 0
        var renderingError: (any Error)?
        let data = renderer.pdfData { context in
            let drawer = PDFDocumentDrawerHelper(
                context: context,
                documentSize: documentSize,
                headerGenerator: document.headerGenerator,
                labelRenderer: PDFLabelRenderer(),
                pageLayout: blockLayout,
            )
            drawer.startNextPage()
            do {
                for content in document.content {
                    switch content {
                    case let .title(label):
                        try drawer.draw(label: label)
                    case let .dataBlock(imageData):
                        try drawer.draw(
                            images: imageData,
                            imageRenderer: imageRenderer,
                            rectSeriesLayout: blockLayout,
                        ) {
                            processedImages += 1
                            progress(Double(processedImages) / Double(totalImages))
                        }
                    }
                }
            } catch {
                renderingError = error
            }
        }
        if let renderingError {
            throw renderingError
        } else if let document = PDFDocument(data: data) {
            if totalImages == 0 {
                progress(1)
            }
            return document
        } else {
            throw PDFRenderingError.invalidData
        }
    }
}

private final class PDFDocumentDrawerHelper<Layout: PageLayout> {
    let context: UIGraphicsPDFRendererContext
    private let headerGenerator: any DataBlockHeaderGenerator
    private let pageLayout: (CGRect) -> Layout
    private let documentSize: any PDFDocumentSize
    private let labelRenderer: PDFLabelRenderer
    /// The current position where we are allowed to draw content.
    /// This will change as elements are drawn, as we are not allowed to override them.
    private var contentArea = PDFContentArea()
    private var currentPage = 0

    init(
        context: UIGraphicsPDFRendererContext,
        documentSize: any PDFDocumentSize,
        headerGenerator: any DataBlockHeaderGenerator,
        labelRenderer: PDFLabelRenderer,
        pageLayout: @escaping (CGRect) -> Layout,
    ) {
        self.context = context
        self.documentSize = documentSize
        self.headerGenerator = headerGenerator
        self.labelRenderer = labelRenderer
        self.pageLayout = pageLayout
    }

    /// Throws if unable to draw.
    func draw(label: DataBlockLabel) throws(PDFContentDrawerer.DrawError) {
        let drawerer = PDFContentDrawerer { [self] in
            let currentLayoutEngine = pageLayout(contentArea.currentBounds)
            let attributedString = labelRenderer.makeAttributedTextForLabel(label)
            let width = contentArea.currentBounds.size.width - label.padding.horizontalTotal
            let boundingRect = attributedString.boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: .usesLineFragmentOrigin,
                context: nil,
            )
            let rect = CGRect(
                x: contentArea.currentBounds.minX + label.padding.left,
                y: contentArea.currentBounds.minY + label.padding.top,
                width: width,
                height: boundingRect.height + label.padding.bottom,
            )
            if currentLayoutEngine.isFullyWithinBounds(rect: rect) {
                attributedString.draw(in: rect)
                contentArea.didDrawContent(at: rect)
                return .success(.didDrawToDocument)
            } else {
                return .failure(.insufficientSpace)
            }
        } makeNewPage: { [self] in
            startNextPage()
        }

        try drawerer.drawContent()
    }

    /// Throws if unable to draw.
    ///
    /// `onImageProcessed` is called after each image is dealt with, whether it was drawn or skipped.
    func draw(
        images: [Data],
        imageRenderer: some ImageDataRenderer,
        rectSeriesLayout: @escaping (CGRect) -> some RectSeriesLayout,
        onImageProcessed: () -> Void,
    ) throws(PDFContentDrawerer.DrawError) {
        var currentImageNumberOnPage: UInt = 0
        var currentLayoutEngine = rectSeriesLayout(contentArea.currentBounds)

        for imageData in images {
            defer { currentImageNumberOnPage += 1 }

            let drawerer = PDFContentDrawerer { [self] in
                guard let rect = currentLayoutEngine.rect(atIndex: currentImageNumberOnPage) else {
                    return .failure(.insufficientSpace)
                }
                guard let image = imageRenderer.resizing(to: rect.size).makeImage(fromData: imageData) else {
                    return .failure(.contentMissing)
                }
                image.draw(in: rect)
                contentArea.didDrawContent(at: rect)
                return .success(.didDrawToDocument)
            } makeNewPage: { [self] in
                startNextPage()
                currentImageNumberOnPage = 0
                currentLayoutEngine = rectSeriesLayout(contentArea.currentBounds)
            }

            try drawerer.drawContent()
            onImageProcessed()
        }
    }

    /// Creates a new page and drawable content area.
    func startNextPage() {
        context.beginPage()
        currentPage += 1
        contentArea = PDFContentArea(fullSize: context.pdfContextBounds)
        contentArea.inset(by: documentSize.pointMargins)

        drawHeaderIfNeeded()
    }

    private func drawHeaderIfNeeded() {
        guard let header = headerGenerator.makeHeader(pageNumber: currentPage) else { return }
        for label in header.allHeaderLabels {
            let headerBottomSpacing = 8.0
            let attributedString = labelRenderer.makeAttributedTextForHeader(text: label.text, position: label.position)
            let width = contentArea.currentBounds.width / 2
            let boundingRect = attributedString.boundingRect(
                with: CGSize(width: width, height: .greatestFiniteMagnitude),
                options: .usesLineFragmentOrigin,
                context: nil,
            )
            let rect = CGRect(
                x: label.position.xPosition(width: width, margins: documentSize.pointMargins),
                y: documentSize.pointMargins.top,
                width: width,
                height: boundingRect.height + headerBottomSpacing,
            )
            attributedString.draw(in: rect)
            contentArea.didDrawContent(at: rect)
        }
    }
}

// MARK: - Progress

extension DataBlockDocument {
    fileprivate var totalImageCount: Int {
        content.reduce(0) { count, item in
            switch item {
            case .title: count
            case let .dataBlock(images): count + images.count
            }
        }
    }
}

// MARK: - Positioning

extension DataBlockHeader {
    fileprivate var allHeaderLabels: [(text: String, position: PDFLabelHeaderPosition)] {
        var labels = [(String, PDFLabelHeaderPosition)]()
        if let left {
            labels.append((left, .left))
        }
        if let right {
            labels.append((right, .right))
        }
        return labels
    }
}
