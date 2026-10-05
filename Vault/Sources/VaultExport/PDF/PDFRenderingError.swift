import Foundation

public enum PDFRenderingError: Error {
    /// The PDF was unable to be created with the provided input data.
    case invalidData
    /// This platform can't render PDFs yet: the Mac renders them from VAULT-104.
    case unavailableOnThisPlatform
}
