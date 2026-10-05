// The Mac's snapshots of QR codes come with VAULT-104.
#if canImport(UIKit)
import Foundation
import ImageTools
import TestHelpers
import Testing
import UIKit

@MainActor
struct QRCodeImageRendererSnapshotTests {
    let sut = QRCodeImageRenderer()

    @Test
    func makeImage_generatesWithEmptyData() throws {
        let image = try #require(sut.makeImage(fromData: Data()))

        assertSnapshot(of: image, as: .image)
    }

    @Test
    func makeImage_generatesWithSomeData() throws {
        let data = Data(repeating: 0xFF, count: 200)
        let image = try #require(sut.makeImage(fromData: data))

        assertSnapshot(of: image, as: .image)
    }
}
#endif
