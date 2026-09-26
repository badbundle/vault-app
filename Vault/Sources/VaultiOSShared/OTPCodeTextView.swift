import SwiftUI
public import VaultFeed
#if canImport(UIKit)
import UIKit
#endif

/// Renders an OTP code in the chunked, monospaced style used across all
/// surfaces that present a code (in-app preview tile, widget, etc.). Lives in
/// `VaultiOSShared` rather than `VaultiOS` so that lightweight surfaces — most
/// notably WidgetKit extensions — can reuse the exact same rendering without
/// pulling in the full `VaultiOS` dependency graph.
public struct OTPCodeTextView: View {
    public var codeState: OTPCodeState
    public var scaledDigitSpacing: Double

    public init(codeState: OTPCodeState, scaledDigitSpacing: Double = 8) {
        self.codeState = codeState
        self.scaledDigitSpacing = scaledDigitSpacing
    }

    public var body: some View {
        switch codeState {
        case .notReady, .finished, .obfuscated:
            placeholderCode(digits: 6)
                .transition(.blurReplace(.downUp))
        case let .locked(code):
            placeholderCode(digits: code.count)
                .transition(.blurReplace(.downUp))
        case let .error(_, digits):
            placeholderCode(digits: digits)
                .foregroundStyle(.red)
                .transition(.blurReplace(.downUp))
        case let .visible(code):
            makeCodeView(text: code)
                .transition(.blurReplace(.downUp))
        }
    }

    private func placeholderCode(digits: Int) -> some View {
        makeCodeView(text: String(repeating: "•", count: digits))
    }

    private func makeCodeView(text: String) -> some View {
        CodeChunksLayout(spacing: spacing) {
            // Chunks are identified by position, so a new code updates the
            // same views rather than replacing every one.
            ForEach(Array(splitText(text: text).enumerated()), id: \.offset) { _, chunk in
                Text(chunk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.1)
                    .multilineTextAlignment(.leading)
            }
        }
    }

    private var spacing: Double {
        #if canImport(UIKit)
        UIFontMetrics.default.scaledValue(for: scaledDigitSpacing)
        #else
        scaledDigitSpacing
        #endif
    }

    private func splitText(text: String) -> [String] {
        Array(text).chunked(by: chunkSize(length: text.count))
    }

    private func chunkSize(length: Int) -> Int {
        switch length {
        case 0 ..< 6:
            length
        case let x where x.isMultiple(of: 3):
            3
        case let x where x.isMultiple(of: 4):
            4
        case let x where x.isMultiple(of: 5):
            5
        default:
            3
        }
    }
}

/// Lays a code's chunks out in a row, scaling every chunk and gap down by the
/// same factor when the row is narrower than they are, so every digit stays
/// the same size.
///
/// An `HStack` gives the least flexible chunk its full width first, so the
/// lone last digit of a 7-digit code would stay full size while the chunks
/// before it shrink.
private struct CodeChunksLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let frames = frames(of: subviews, width: proposal.width)
        return CGSize(
            width: frames.last?.maxX ?? 0,
            height: frames.map(\.maxY).max() ?? 0,
        )
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        for (subview, frame) in zip(subviews, frames(of: subviews, width: bounds.width)) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size),
            )
        }
    }

    func explicitAlignment(
        of guide: VerticalAlignment,
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout (),
    ) -> CGFloat? {
        guard guide == .firstTextBaseline || guide == .lastTextBaseline,
              let first = subviews.first,
              let frame = frames(of: subviews, width: bounds.width).first
        else { return nil }
        return frame.minY + first.dimensions(in: ProposedViewSize(frame.size))[guide]
    }

    /// Each chunk's frame, relative to the row's top-leading corner, with
    /// their baselines lined up.
    private func frames(of subviews: Subviews, width: CGFloat?) -> [CGRect] {
        let idealSizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let gaps = spacing * CGFloat(max(subviews.count - 1, 0))
        let idealWidth = idealSizes.map(\.width).reduce(0, +) + gaps
        let scale: CGFloat = if let width, idealWidth > width, idealWidth > 0 {
            width / idealWidth
        } else {
            1
        }

        var nextX: CGFloat = 0
        var placed: [(x: CGFloat, dimensions: ViewDimensions)] = []
        for (subview, idealSize) in zip(subviews, idealSizes) {
            let dimensions = subview.dimensions(in: ProposedViewSize(width: idealSize.width * scale, height: nil))
            placed.append((nextX, dimensions))
            nextX += dimensions.width + spacing * scale
        }

        let baseline = placed.map { $0.dimensions[.firstTextBaseline] }.max() ?? 0
        return placed.map { originX, dimensions in
            CGRect(
                x: originX,
                y: baseline - dimensions[.firstTextBaseline],
                width: dimensions.width,
                height: dimensions.height,
            )
        }
    }
}

extension [Character] {
    fileprivate func chunked(by chunkSize: Int) -> [String] {
        stride(from: startIndex, to: endIndex, by: chunkSize).map {
            let startIndex = $0
            let endIndex = Swift.min($0 + chunkSize, count)
            let actual = Array(self[startIndex ..< endIndex])
            return String(actual)
        }
    }
}

#Preview {
    VStack {
        OTPCodeTextView(
            codeState: .visible("123456"),
        )

        OTPCodeTextView(
            codeState: .visible("1234567"),
        )

        OTPCodeTextView(
            codeState: .visible("12345678"),
        )

        OTPCodeTextView(
            codeState: .visible("123456789"),
        )

        OTPCodeTextView(
            codeState: .visible("1234567890"),
        )

        OTPCodeTextView(
            codeState: .finished,
        )

        OTPCodeTextView(
            codeState: .error(.init(userTitle: "Any", debugDescription: "Any"), digits: 6),
        )
    }
    .font(.system(.largeTitle, design: .monospaced))
}
