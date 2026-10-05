import Foundation

/// @mockable
public protocol ImageDataRenderer {
    /// Makes an image from the provided data.
    /// The way this transformation happens is down to each individual renderer.
    func makeImage(fromData data: Data) -> PlatformImage?
}

// MARK: - Transform

extension ImageDataRenderer {
    public func transform(_ operation: some ImageTransformer) -> some ImageDataRenderer {
        TransformedImageRenderer(renderer: self, transformer: operation)
    }
}

// MARK: - Common Transforms

extension ImageDataRenderer {
    public func resizing(to size: CGSize) -> some ImageDataRenderer {
        transform(ResizeImageTransformer(size: size))
    }
}
