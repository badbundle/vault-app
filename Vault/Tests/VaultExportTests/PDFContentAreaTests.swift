import Foundation
import TestHelpers
import Testing
@testable import VaultExport

struct PDFContentAreaTests {
    @Test
    func init_currentBoundsIsZero() {
        let sut = PDFContentArea()

        #expect(sut.currentBounds == .zero)
    }

    @Test
    func init_currentBoundsIsProvidedRect() {
        let rect = CGRect(origin: .init(x: 10, y: 10), size: .init(width: 100, height: 100))
        let sut = PDFContentArea(fullSize: rect)

        #expect(sut.currentBounds == rect)
    }

    @Test
    func inset_insetsCurrentBoundsByAmount() {
        let rect = CGRect(origin: .init(x: 10, y: 10), size: .init(width: 100, height: 100))
        var sut = PDFContentArea(fullSize: rect)

        let insets = PlatformEdgeInsets(top: 10, left: 11, bottom: 12, right: 13)
        sut.inset(by: insets)

        #expect(sut.currentBounds == rect.inset(by: insets))
    }

    @Test
    func didDrawContent_hasNoEffectOnZero() {
        var sut = PDFContentArea()

        sut.didDrawContent(at: .zero)

        #expect(sut.currentBounds == .zero)
    }

    @Test
    func didDrawContent_engulfsDrawnAreaVerticallyByOrigin() {
        let rect = CGRect(origin: .init(x: 10, y: 10), size: .init(width: 100, height: 100))
        var sut = PDFContentArea(fullSize: rect)

        sut.didDrawContent(at: .init(origin: .init(x: 20, y: 20), size: .zero))

        #expect(sut.currentBounds == .init(x: 10.0, y: 20.0, width: 100.0, height: 90.0))
    }

    @Test
    func didDrawContent_engulfsDrawnAreaVerticallyByHeight() {
        let rect = CGRect(origin: .init(x: 10, y: 10), size: .init(width: 100, height: 100))
        var sut = PDFContentArea(fullSize: rect)

        sut.didDrawContent(at: .init(origin: .init(x: 5, y: 5), size: .init(width: 10, height: 25)))

        #expect(sut.currentBounds == .init(x: 10.0, y: 30.0, width: 100.0, height: 80.0))
    }

    @Test
    func didDrawContent_hasNoEffectIfAboveCurrentArea() {
        let rect = CGRect(origin: .init(x: 10, y: 10), size: .init(width: 100, height: 100))
        var sut = PDFContentArea(fullSize: rect)

        sut.didDrawContent(at: .init(origin: .init(x: 5, y: 5), size: .zero))

        #expect(sut.currentBounds == rect)
    }
}
