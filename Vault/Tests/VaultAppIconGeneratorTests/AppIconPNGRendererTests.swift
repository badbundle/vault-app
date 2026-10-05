import CoreGraphics
import Foundation
import ImageIO
import Testing
import VaultAppIcon
@testable import VaultAppIconGenerator

@MainActor
struct AppIconPNGRendererTests {
    @Test(arguments: VaultAppIconAppearance.allCases)
    func pngData_producesPNGOfRequestedSize(appearance: VaultAppIconAppearance) throws {
        let data = try AppIconPNGRenderer.pngData(appearance: appearance, pixelSize: 64)

        #expect(data.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
        let image = try #require(decode(data))
        #expect(image.width == 64)
        #expect(image.height == 64)
    }

    @Test
    func pngData_lightHasNoAlphaChannel() throws {
        let data = try AppIconPNGRenderer.pngData(appearance: .light, pixelSize: 16)
        let alpha = try hasAlpha(data)
        #expect(alpha == false)
    }

    @Test(arguments: [VaultAppIconAppearance.dark, .tinted])
    func pngData_transparentAppearancesKeepAlphaChannel(appearance: VaultAppIconAppearance) throws {
        let data = try AppIconPNGRenderer.pngData(appearance: appearance, pixelSize: 16)
        let alpha = try hasAlpha(data)
        #expect(alpha == true)
    }

    private func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func hasAlpha(_ data: Data) throws -> Bool {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        return properties[kCGImagePropertyHasAlpha as String] as? Bool ?? false
    }
}

@MainActor
struct MacAppIconPNGRendererTests {
    @Test
    func macPNGData_isTheSizeAskedForWithTransparentCorners() throws {
        let data = try AppIconPNGRenderer.macPNGData(pixelSize: 64)

        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 64)
        #expect(image.height == 64)
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        #expect(properties[kCGImagePropertyHasAlpha as String] as? Bool == true)
    }
}
