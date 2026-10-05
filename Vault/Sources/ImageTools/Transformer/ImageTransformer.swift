import Foundation

/// @mockable
public protocol ImageTransformer {
    func tranform(image: PlatformImage) -> PlatformImage
}
