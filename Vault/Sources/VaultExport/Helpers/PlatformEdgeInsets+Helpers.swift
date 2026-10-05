import CoreGraphics
import Foundation

extension PlatformEdgeInsets {
    public var verticalTotal: CGFloat {
        top + bottom
    }

    public var horizontalTotal: CGFloat {
        left + right
    }

    public init(uniform: CGFloat) {
        self = .init(top: uniform, left: uniform, bottom: uniform, right: uniform)
    }
}

#if !canImport(UIKit)
extension PlatformEdgeInsets {
    /// No insets, as `UIEdgeInsets.zero` is on iOS.
    public static var zero: PlatformEdgeInsets {
        .init(top: 0, left: 0, bottom: 0, right: 0)
    }
}

extension NSEdgeInsets: @retroactive Equatable {
    public static func == (lhs: NSEdgeInsets, rhs: NSEdgeInsets) -> Bool {
        lhs.top == rhs.top && lhs.left == rhs.left && lhs.bottom == rhs.bottom && lhs.right == rhs.right
    }
}

extension CGRect {
    /// The rectangle inside these insets, as UIKit's `inset(by:)` gives it on iOS.
    public func inset(by insets: PlatformEdgeInsets) -> CGRect {
        CGRect(
            x: minX + insets.left,
            y: minY + insets.top,
            width: width - insets.horizontalTotal,
            height: height - insets.verticalTotal,
        )
    }
}
#endif
