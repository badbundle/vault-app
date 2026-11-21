import CoreGraphics
import Foundation

/// A drawing in a `DataBlockDocument`, such as a backup's seal, as wide as the page's content and `height` tall.
///
/// It draws itself, in the rect it's given, into the page's context. The context's y axis points down, as UIKit's
/// does, on iOS and the Mac. Like a label, it moves to the next page if there isn't room for it on this one.
public struct DataBlockFigure {
    /// What the figure is, for debugging and tests.
    public var name: String
    public var height: CGFloat
    public var padding: PlatformEdgeInsets
    public var draw: (CGContext, CGRect) -> Void

    public init(
        name: String,
        height: CGFloat,
        padding: PlatformEdgeInsets,
        draw: @escaping (CGContext, CGRect) -> Void,
    ) {
        self.name = name
        self.height = height
        self.padding = padding
        self.draw = draw
    }
}
