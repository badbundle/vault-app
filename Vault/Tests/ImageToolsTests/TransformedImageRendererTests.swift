import Foundation
import TestHelpers
import Testing
@testable import ImageTools

struct TransformedImageRendererTests {
    @Test
    func makeImage_nilFromRendererIsNil() {
        let renderer = ImageDataRendererMock()
        renderer.makeImageHandler = { _ in nil }
        let transformer = ImageTransformerMock()
        let sut = TransformedImageRenderer(renderer: renderer, transformer: transformer)

        #expect(sut.makeImage(fromData: Data()) == nil)
    }

    @Test
    func makeImage_appliesTransformOnce() {
        let imageData = Data(repeating: 0x44, count: 45)
        let renderer = ImageDataRendererMock()
        renderer.makeImageHandler = { _ in PlatformImage() }
        let transformer = ImageTransformerMock()
        // mockolo has a default image for UIImage, but not NSImage.
        transformer.tranformHandler = { $0 }
        let sut = TransformedImageRenderer(renderer: renderer, transformer: transformer)

        let image = sut.makeImage(fromData: imageData)

        #expect(image != nil)
        #expect(renderer.makeImageCallCount == 1)
        #expect(transformer.tranformCallCount == 1)
    }
}
