import Foundation
import PDFKit

/// @mockable(typealias: Document = DataBlockDocument)
public protocol PDFDocumentRenderer<Document> {
    associatedtype Document

    /// Renders the document, reporting progress as it goes.
    ///
    /// `progress` is called synchronously on the rendering thread with values in `0...1`. A successful
    /// render always ends with a report of `1`.
    func render(document: Document, progress: @escaping (Double) -> Void) throws -> PDFDocument
}

extension PDFDocumentRenderer {
    /// Renders the document without observing progress.
    public func render(document: Document) throws -> PDFDocument {
        try render(document: document, progress: { _ in })
    }
}
