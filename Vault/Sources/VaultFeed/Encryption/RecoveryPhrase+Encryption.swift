import Foundation
import VaultCore

extension RecoveryPhrase: VaultItemEncryptable {
    public init(encryptedContainer: EncryptedContainer) {
        self = .init(
            title: encryptedContainer.title,
            words: encryptedContainer.words,
            standard: encryptedContainer.standard.toStandard(),
            passphrase: encryptedContainer.passphrase,
            contents: encryptedContainer.contents,
        )
    }

    public func makeEncryptedContainer() throws -> EncryptedContainer {
        EncryptedContainer(
            title: title,
            words: words,
            standard: .init(standard: standard),
            passphrase: passphrase,
            contents: contents,
        )
    }

    /// Resilient format that is used during encryption/decryption.
    public struct EncryptedContainer: VaultItemEncryptedContainer {
        public var itemIdentifier: String = VaultIdentifiers.Item.recoveryPhrase
        public var title: String
        var words: [String]
        var standard: Standard
        var passphrase: String
        var contents: String

        init(title: String, words: [String], standard: Standard, passphrase: String, contents: String) {
            self.title = title
            self.words = words
            self.standard = standard
            self.passphrase = passphrase
            self.contents = contents
        }

        enum CodingKeys: String, CodingKey {
            case itemIdentifier
            case title
            case words
            case standard
            case passphrase
            case contents
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            itemIdentifier = try container.decode(String.self, forKey: .itemIdentifier)
            title = try container.decode(String.self, forKey: .title)
            words = try container.decode([String].self, forKey: .words)
            // Tolerate fields that a future version might drop, so the words themselves are never lost.
            standard = try container.decodeIfPresent(Standard.self, forKey: .standard) ?? .other
            passphrase = try container.decodeIfPresent(String.self, forKey: .passphrase) ?? ""
            contents = try container.decodeIfPresent(String.self, forKey: .contents) ?? ""
        }

        enum Standard: String, Codable {
            case bip39 = "BIP39"
            case slip39 = "SLIP39"
            case electrum = "ELECTRUM"
            case monero = "MONERO"
            case other = "OTHER"

            init(standard: RecoveryPhraseStandard) {
                self = switch standard {
                case .bip39: .bip39
                case .slip39: .slip39
                case .electrum: .electrum
                case .monero: .monero
                case .other: .other
                }
            }

            /// A standard added in a later version decodes as `.other`, so the phrase can still be shown, just not
            /// validated.
            init(from decoder: any Decoder) throws {
                let rawValue = try decoder.singleValueContainer().decode(String.self)
                self = Standard(rawValue: rawValue) ?? .other
            }

            func toStandard() -> RecoveryPhraseStandard {
                switch self {
                case .bip39: .bip39
                case .slip39: .slip39
                case .electrum: .electrum
                case .monero: .monero
                case .other: .other
                }
            }
        }
    }
}
