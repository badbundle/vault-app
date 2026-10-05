import Foundation
import PDFKit
import VaultExport

/// A stubable `PlatformPDFRenderer` that can return custom data.
class PlatformPDFRendererStub: PlatformPDFRenderer {
    var pdfDataValue = Data()
    override func pdfData(actions _: (PlatformPDFRendererContext) -> Void) -> Data {
        pdfDataValue
    }
}
