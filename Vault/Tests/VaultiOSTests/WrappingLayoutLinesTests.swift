import Foundation
import Testing
@testable import VaultiOS

struct WrappingLayoutLinesTests {
    @Test
    func noSubviews_hasNoSize() {
        let sut = WrappingLayoutLines(sizes: [], maxWidth: 100, spacing: 8)

        #expect(sut.frames.isEmpty)
        #expect(sut.size == .zero)
    }

    @Test
    func subviewsThatFit_shareOneLineWithSpacing() {
        let sut = WrappingLayoutLines(
            sizes: [CGSize(width: 40, height: 20), CGSize(width: 30, height: 20)],
            maxWidth: 100,
            spacing: 8,
        )

        #expect(sut.frames == [
            CGRect(x: 0, y: 0, width: 40, height: 20),
            CGRect(x: 48, y: 0, width: 30, height: 20),
        ])
        #expect(sut.size == CGSize(width: 78, height: 20))
    }

    @Test
    func subviewThatExactlyFills_staysOnTheLine() {
        let sut = WrappingLayoutLines(
            sizes: [CGSize(width: 46, height: 20), CGSize(width: 46, height: 20)],
            maxWidth: 100,
            spacing: 8,
        )

        #expect(sut.frames.map(\.minY) == [0, 0])
        #expect(sut.size == CGSize(width: 100, height: 20))
    }

    @Test
    func subviewThatOverflows_wrapsToANewLine() {
        let sut = WrappingLayoutLines(
            sizes: [CGSize(width: 60, height: 20), CGSize(width: 50, height: 20), CGSize(width: 30, height: 20)],
            maxWidth: 100,
            spacing: 8,
        )

        #expect(sut.frames == [
            CGRect(x: 0, y: 0, width: 60, height: 20),
            CGRect(x: 0, y: 28, width: 50, height: 20),
            CGRect(x: 58, y: 28, width: 30, height: 20),
        ])
        #expect(sut.size == CGSize(width: 88, height: 48))
    }

    @Test
    func subviewWiderThanALine_isNarrowedToTheLine() {
        let sut = WrappingLayoutLines(
            sizes: [CGSize(width: 30, height: 20), CGSize(width: 150, height: 20)],
            maxWidth: 100,
            spacing: 8,
        )

        #expect(sut.frames == [
            CGRect(x: 0, y: 0, width: 30, height: 20),
            CGRect(x: 0, y: 28, width: 100, height: 20),
        ])
        #expect(sut.size == CGSize(width: 100, height: 48))
    }

    @Test
    func shorterSubviews_centerOnTheirLine() {
        let sut = WrappingLayoutLines(
            sizes: [CGSize(width: 40, height: 30), CGSize(width: 40, height: 20)],
            maxWidth: 100,
            spacing: 8,
        )

        #expect(sut.frames == [
            CGRect(x: 0, y: 0, width: 40, height: 30),
            CGRect(x: 48, y: 5, width: 40, height: 20),
        ])
        #expect(sut.size == CGSize(width: 88, height: 30))
    }

    @Test
    func unboundedWidth_keepsEverythingOnOneLine() {
        let sut = WrappingLayoutLines(
            sizes: Array(repeating: CGSize(width: 500, height: 20), count: 3),
            maxWidth: .infinity,
            spacing: 8,
        )

        #expect(sut.frames.map(\.minY) == [0, 0, 0])
        #expect(sut.size == CGSize(width: 1516, height: 20))
    }
}
