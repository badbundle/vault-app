import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct DataBlockLabel {
    public var text: String
    public var font: PlatformFont
    public var textColor: PlatformColor
    public var padding: PlatformEdgeInsets

    public init(text: String, font: PlatformFont, textColor: PlatformColor = .black, padding: PlatformEdgeInsets) {
        self.text = text
        self.font = font
        self.textColor = textColor
        self.padding = padding
    }
}
