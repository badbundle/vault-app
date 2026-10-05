import CoreGraphics
import CoreImage
import Foundation

/// Renders the provided data into a QR code.
public struct QRCodeImageRenderer: ImageDataRenderer {
    public init() {}

    public func makeImage(fromData data: Data) -> PlatformImage? {
        guard let pngData = CIFilter.qrCode(data: data)?.outputImage?.asPNG() else {
            return nil
        }
        return PlatformImage(data: pngData)
    }
}

// MARK: - QR code generation

extension CIFilter {
    /// Create a filter to produce a QRCode from the provided data.
    ///
    /// - Returns: `nil` only if the filter cannot be loaded internally.
    fileprivate static func qrCode(data: Data) -> CIFilter? {
        let filter = CIFilter(name: "CIQRCodeGenerator")
        filter?.setValue(data, forKey: "inputMessage")
        return filter
    }
}

extension CIImage {
    /// Convert this image into PNG data, in the `sRGB` color space.
    ///
    /// - Returns: `nil` if the image cannot be rendered.
    fileprivate func asPNG() -> Data? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }
        let context = CIContext()
        return context.pngRepresentation(of: self, format: .RGBA8, colorSpace: colorSpace)
    }
}
