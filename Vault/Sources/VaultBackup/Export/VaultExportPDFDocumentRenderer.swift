import Foundation
import PDFKit
import VaultCore
import VaultExport

/// A renderer for an exported vault.
///
/// Internally uses a data block renderer to render the data to a PDF.
struct VaultExportPDFDocumentRenderer<Renderer: PDFDocumentRenderer>: PDFDocumentRenderer
    where
    Renderer.Document == DataBlockDocument
{
    typealias Document = VaultExportPayload

    private let renderer: Renderer
    private let dataShardBuilder: DataShardBuilder
    private let attacher: any VaultBackupPDFAttacher

    init(renderer: Renderer, dataShardBuilder: DataShardBuilder, attacher: any VaultBackupPDFAttacher) {
        self.renderer = renderer
        self.dataShardBuilder = dataShardBuilder
        self.attacher = attacher
    }

    func render(document: VaultExportPayload, progress: @escaping (Double) -> Void) throws -> PDFDocument {
        let generator = VaultExportDataBlockGenerator(payload: document, dataShardBuilder: dataShardBuilder)

        /// Each pass renders every code, so each pass owns half of the overall progress.
        func render(totalPageCount: Int?, progressRange: ClosedRange<Double>) throws -> PDFDocument {
            let finalPageCount = totalPageCount ?? 0
            let document = try generator.makeDocument(knownPageCount: finalPageCount)
            return try renderer.render(document: document) { fraction in
                let span = progressRange.upperBound - progressRange.lowerBound
                progress(progressRange.lowerBound + span * fraction)
            }
        }

        // The first pass render determines how many pages there actually are.
        let firstPassRender = try render(totalPageCount: nil, progressRange: 0 ... 0.5)
        var finalRender = try render(totalPageCount: firstPassRender.pageCount, progressRange: 0.5 ... 1)

        // Attach the encrypted vault as well, so we can read it easily and automatically.
        try attacher.attach(vault: document.encryptedVault, to: &finalRender)

        return finalRender
    }
}
