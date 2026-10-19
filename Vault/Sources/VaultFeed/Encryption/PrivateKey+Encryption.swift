import Foundation
import VaultCore

extension PrivateKey: VaultItemEncryptable {
    public init(encryptedContainer: EncryptedContainer) {
        self = .init(
            title: encryptedContainer.title,
            key: encryptedContainer.key,
            contents: encryptedContainer.contents,
        )
    }

    public func makeEncryptedContainer() throws -> EncryptedContainer {
        EncryptedContainer(title: title, key: key, contents: contents)
    }

    /// Resilient format that is used during encryption/decryption.
    ///
    /// The key's format isn't stored: it's recognized from the key each time it's shown, so a later version that
    /// recognizes more formats recognizes keys saved before it too.
    public struct EncryptedContainer: VaultItemEncryptedContainer {
        public var itemIdentifier: String = VaultIdentifiers.Item.privateKey
        public var title: String
        var key: String
        var contents: String

        init(title: String, key: String, contents: String) {
            self.title = title
            self.key = key
            self.contents = contents
        }

        enum CodingKeys: String, CodingKey {
            case itemIdentifier
            case title
            case key
            case contents
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            itemIdentifier = try container.decode(String.self, forKey: .itemIdentifier)
            title = try container.decode(String.self, forKey: .title)
            key = try container.decode(String.self, forKey: .key)
            // Tolerate a description a future version might drop, so the key itself is never lost.
            contents = try container.decodeIfPresent(String.self, forKey: .contents) ?? ""
        }
    }
}
