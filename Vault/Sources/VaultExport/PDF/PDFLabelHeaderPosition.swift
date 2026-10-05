import CoreGraphics
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The position that a header label can be rendered in.
enum PDFLabelHeaderPosition {
    case left, right

    var textAlignment: NSTextAlignment {
        switch self {
        case .left: .left
        case .right: .right
        }
    }

    var lineBreakMode: NSLineBreakMode {
        switch self {
        case .left: .byTruncatingTail
        case .right: .byTruncatingHead
        }
    }

    func xPosition(width: CGFloat, margins: PlatformEdgeInsets) -> CGFloat {
        switch self {
        case .left: margins.left
        case .right: width + margins.left
        }
    }
}
