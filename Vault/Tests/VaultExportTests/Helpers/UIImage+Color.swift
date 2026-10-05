// The Mac renders PDFs from VAULT-104.
#if canImport(UIKit)
import UIKit

extension UIImage {
    static func from(color: UIColor, size: CGSize = .init(width: 1, height: 1)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            context.cgContext.setFillColor(color.cgColor)
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
#endif
