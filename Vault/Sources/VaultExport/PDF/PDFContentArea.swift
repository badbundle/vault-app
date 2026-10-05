import CoreGraphics
import Foundation

/// Manages the drawing area on a PDF document.
struct PDFContentArea {
    private(set) var currentBounds: CGRect

    init(fullSize: CGRect = .zero) {
        currentBounds = fullSize
    }

    /// Inset the content area by the given amount.
    mutating func inset(by insets: PlatformEdgeInsets) {
        currentBounds = currentBounds.inset(by: insets)
    }

    /// Some content was drawn at this position in the area and nothing should
    /// be able to be drawn here again.
    ///
    /// Removes vertical height from the drawing area that engulfs this position.
    /// If no additonal height removal is needed, do nothing.
    mutating func didDrawContent(at rect: CGRect) {
        let amountInNewSpace = rect.maxY - currentBounds.minY
        let heightToRemove = max(0, amountInNewSpace)
        // Remove the height from the top of the content area.
        currentBounds.origin.y += heightToRemove
        currentBounds.size.height -= heightToRemove
    }
}
