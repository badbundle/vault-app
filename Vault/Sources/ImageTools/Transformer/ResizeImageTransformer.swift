// The Mac resizes images from VAULT-104.
#if canImport(UIKit)
import UIKit

public struct ResizeImageTransformer: ImageTransformer {
    public let size: CGSize

    public init(size: CGSize) {
        self.size = size
    }

    public func tranform(image: UIImage) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            context.cgContext.interpolationQuality = .none
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
#endif
