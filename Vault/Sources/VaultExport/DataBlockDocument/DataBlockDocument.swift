import Foundation

public struct DataBlockDocument {
    /// Header generator for a given page number.
    public var headerGenerator: any DataBlockHeaderGenerator
    /// The content to be drawn to the document, in the order provided here.
    public var content: [Content]

    /// Content that can be rendered to the document.
    public enum Content: CustomDebugStringConvertible {
        /// A piece of text rendered as a label.
        case title(DataBlockLabel)
        /// A series of data blobs, which should be rendered in a user-visible format to the document.
        /// A QR code for each data item might be a good idea :)
        case dataBlock([Data])
        /// A drawing as wide as the page's content, which draws itself.
        case figure(DataBlockFigure)

        public var debugDescription: String {
            switch self {
            case let .title(label): "TITLE: \(label.text)"
            case let .dataBlock(data): "DATA BLOCK: count:\(data.count)"
            case let .figure(figure): "FIGURE: \(figure.name)"
            }
        }
    }

    public init(
        headerGenerator: any DataBlockHeaderGenerator = NoHeaderDataBlockHeaderGenerator(),
        content: [Content],
    ) {
        self.headerGenerator = headerGenerator
        self.content = content
    }
}
