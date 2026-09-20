import Foundation
import ImageTools
import PDFKit
import VaultCore
import VaultExport

public struct VaultBackupPDFGenerator {
    public var size: any PDFDocumentSize
    public var documentTitle: String
    public var applicationName: String
    public var authorName: String

    public init(size: any PDFDocumentSize, documentTitle: String, applicationName: String, authorName: String) {
        self.size = size
        self.documentTitle = documentTitle
        self.applicationName = applicationName
        self.authorName = authorName
    }

    /// Renders the payload to a PDF.
    ///
    /// `progress` is called synchronously on the rendering thread with values in `0...1`, ending at `1`.
    public func makePDF(
        payload: VaultExportPayload,
        progress: @escaping (Double) -> Void = { _ in },
    ) throws -> PDFDocument {
        let blockDocumentRenderer = PDFDataBlockDocumentRenderer(
            documentSize: size,
            rendererFactory: PDFDocumentPageRendererFactory(
                size: size,
                applicationName: applicationName,
                authorName: authorName,
                documentTitle: documentTitle,
            ),
            imageRenderer: QRCodeImageRenderer(),
            blockLayout: { rect in
                VerticalTilingDataBlockLayout(
                    bounds: rect,
                    tilesPerRow: size.idealNumberOfHorizontalSquaresForPaperSize,
                    spacing: 5,
                )
            },
        )
        let documentRenderer = VaultExportPDFDocumentRenderer(
            renderer: blockDocumentRenderer,
            dataShardBuilder: dataShardBuilder,
            attacher: VaultBackupPDFAttacherImpl(),
        )
        return try documentRenderer.render(document: payload, progress: progress)
    }

    private var dataShardBuilder: DataShardBuilder {
        #if DEBUG
        // Use a deterministic group ID in debug builds for deterministic test results.
        return DataShardBuilder(groupIDGenerator: { 0 })
        #else
        return DataShardBuilder()
        #endif
    }
}
