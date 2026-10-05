import Foundation

/// Applies a certain `ImageTransformer` to a `ImageDataRenderer`.
///
/// All images output by the `ImageDataRenderer` will be modified by the `ImageTransformer`.
public struct TransformedImageRenderer<Renderer: ImageDataRenderer, Transformer: ImageTransformer>: ImageDataRenderer {
    private var renderer: Renderer
    private var transformer: Transformer

    public init(renderer: Renderer, transformer: Transformer) {
        self.renderer = renderer
        self.transformer = transformer
    }

    public func makeImage(fromData data: Data) -> PlatformImage? {
        guard let image = renderer.makeImage(fromData: data) else {
            return nil
        }
        return transformer.tranform(image: image)
    }
}
