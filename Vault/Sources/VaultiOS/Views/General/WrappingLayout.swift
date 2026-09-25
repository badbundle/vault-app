import Foundation
import SwiftUI

/// Lays its subviews out left to right at their ideal sizes, starting a new
/// line whenever the next one wouldn't fit, like words in a paragraph.
///
/// A subview wider than the whole line gets a line of its own at the full
/// width, so text inside it can truncate.
struct WrappingLayout: Layout {
    /// The gap between neighbors on a line, and between lines.
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let lines = WrappingLayoutLines(
            sizes: idealSizes(of: subviews, maxWidth: proposal.width),
            maxWidth: proposal.width ?? .infinity,
            spacing: spacing,
        )
        return lines.size
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let lines = WrappingLayoutLines(
            sizes: idealSizes(of: subviews, maxWidth: bounds.width),
            maxWidth: bounds.width,
            spacing: spacing,
        )
        for (index, frame) in lines.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size),
            )
        }
    }

    private func idealSizes(of subviews: Subviews, maxWidth: CGFloat?) -> [CGSize] {
        subviews.map { subview in
            let size = subview.sizeThatFits(.unspecified)
            guard let maxWidth, size.width > maxWidth else { return size }
            return subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
        }
    }
}

/// Where `WrappingLayout` puts each subview, worked out from their sizes
/// alone so it can be tested without any views.
struct WrappingLayoutLines: Equatable {
    /// Each subview's frame, relative to the layout's top-leading corner.
    private(set) var frames: [CGRect] = []
    /// The size of the lines together: the widest line by all of them.
    private(set) var size: CGSize = .zero

    init(sizes: [CGSize], maxWidth: CGFloat, spacing: CGFloat) {
        var lineStart = frames.startIndex
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subviewSize in sizes {
            let width = min(subviewSize.width, maxWidth)
            if x > 0, x + width > maxWidth {
                centerLine(from: lineStart, height: lineHeight)
                lineStart = frames.endIndex
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: width, height: subviewSize.height))
            size.width = max(size.width, x + width)
            x += width + spacing
            lineHeight = max(lineHeight, subviewSize.height)
        }
        centerLine(from: lineStart, height: lineHeight)
        size.height = frames.isEmpty ? 0 : y + lineHeight
    }

    /// Centers shorter subviews vertically within their line.
    private mutating func centerLine(from start: Int, height: CGFloat) {
        for index in start ..< frames.endIndex {
            frames[index].origin.y += (height - frames[index].height) / 2
        }
    }
}
