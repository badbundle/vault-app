#if canImport(UIKit)
import UIKit

/// The platform's font type: `UIFont` on iOS, `NSFont` on the Mac.
public typealias PlatformFont = UIFont
/// The platform's color type: `UIColor` on iOS, `NSColor` on the Mac.
public typealias PlatformColor = UIColor
/// The platform's edge insets: `UIEdgeInsets` on iOS, `NSEdgeInsets` on the Mac.
public typealias PlatformEdgeInsets = UIEdgeInsets
/// What draws a PDF: `UIGraphicsPDFRenderer` on iOS, `CoreGraphicsPDFRenderer` on the Mac.
public typealias PlatformPDFRenderer = UIGraphicsPDFRenderer
/// The context a PDF is drawn in: `UIGraphicsPDFRendererContext` on iOS, `CoreGraphicsPDFRendererContext` on the Mac.
public typealias PlatformPDFRendererContext = UIGraphicsPDFRendererContext
#elseif canImport(AppKit)
import AppKit

/// The platform's font type: `UIFont` on iOS, `NSFont` on the Mac.
public typealias PlatformFont = NSFont
/// The platform's color type: `UIColor` on iOS, `NSColor` on the Mac.
public typealias PlatformColor = NSColor
/// The platform's edge insets: `UIEdgeInsets` on iOS, `NSEdgeInsets` on the Mac.
public typealias PlatformEdgeInsets = NSEdgeInsets
/// What draws a PDF: `UIGraphicsPDFRenderer` on iOS, `CoreGraphicsPDFRenderer` on the Mac.
public typealias PlatformPDFRenderer = CoreGraphicsPDFRenderer
/// The context a PDF is drawn in: `UIGraphicsPDFRendererContext` on iOS, `CoreGraphicsPDFRendererContext` on the Mac.
public typealias PlatformPDFRendererContext = CoreGraphicsPDFRendererContext
#endif
