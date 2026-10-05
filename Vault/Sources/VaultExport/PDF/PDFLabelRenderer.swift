import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

final class PDFLabelRenderer {
    func makeAttributedTextForHeader(text: String, position: PDFLabelHeaderPosition) -> NSAttributedString {
        let labelFontSize = 9.0
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = position.textAlignment
        paragraphStyle.lineBreakMode = position.lineBreakMode
        return NSAttributedString(
            string: text,
            attributes: [
                NSAttributedString.Key.paragraphStyle: paragraphStyle,
                NSAttributedString.Key.font: PlatformFont.systemFont(ofSize: labelFontSize, weight: .regular),
                NSAttributedString.Key.foregroundColor: PlatformColor.darkGray,
            ],
        )
    }

    func makeAttributedTextForLabel(_ label: DataBlockLabel) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byWordWrapping
        return NSAttributedString(
            string: label.text,
            attributes: [
                NSAttributedString.Key.paragraphStyle: paragraphStyle,
                NSAttributedString.Key.font: label.font,
                NSAttributedString.Key.foregroundColor: label.textColor,
            ],
        )
    }
}
