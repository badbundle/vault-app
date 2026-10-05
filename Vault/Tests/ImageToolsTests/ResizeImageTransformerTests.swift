// The Mac resizes images from VAULT-104.
#if canImport(UIKit)
import Foundation
import ImageTools
import SnapshotTesting
import Testing
import UIKit

struct ResizeImageTransformerTests {
    @Test(arguments: [
        ("small", 20),
        ("medium", 100),
        ("large", 250),
    ])
    func resize_doesNotMakeImageBlurryResizingLarger(sizeName: String, size: Double) throws {
        let image = try exampleImage()

        let sut = ResizeImageTransformer(size: CGSize(width: size, height: size))
        let resizedImage = sut.tranform(image: image)
        assertSnapshot(of: resizedImage, as: .image, named: sizeName)
    }
}

// MARK: - Helpers

extension ResizeImageTransformerTests {
    private func exampleImage() throws -> UIImage {
        let qr = QRCodeImageRenderer()
        let data = Data(repeating: 0xFF, count: 200)
        return try #require(qr.makeImage(fromData: data))
    }
}
#endif
