import Foundation
import VaultCore

/// The format a private key is recognized as, and whether it's valid, for display.
public struct PrivateKeyValidationSummary: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Recognized, and its checksum matches where it has one.
        case valid
        /// Something is wrong with the key, it should be checked.
        case warning
        /// Nothing entered, or a format Vault doesn't check.
        case neutral
    }

    public var kind: Kind
    public var title: String
    public var detail: String
    public var systemIconName: String
    /// The kind of key it is, such as "WIF" or "OpenSSH", or "Other" for a format Vault doesn't recognize. Empty while
    /// there's no key.
    public var kindTitle: String

    public init(validation: PrivateKeyValidation) {
        switch validation.status {
        case let .valid(format):
            kind = .valid
            systemIconName = "checkmark.seal.fill"
            title = localized(key: "privateKeyValidation.valid.title")
            detail = format.localizedDescription
            kindTitle = format.kind.localizedTitle
        case let .invalidChecksum(keyKind):
            kind = .warning
            systemIconName = "exclamationmark.triangle.fill"
            title = localized(key: "privateKeyValidation.invalidChecksum.title")
            detail = localized(key: "privateKeyValidation.invalidChecksum.detail.\(keyKind.localizedTitleWithArticle)")
            kindTitle = keyKind.localizedTitle
        case let .malformed(keyKind, problem):
            kind = .warning
            systemIconName = "exclamationmark.triangle.fill"
            (title, detail) = Self.describe(problem, of: keyKind)
            kindTitle = keyKind.localizedTitle
        case let .publicKey(keyKind):
            kind = .warning
            systemIconName = "exclamationmark.triangle.fill"
            title = localized(key: "privateKeyValidation.publicKey.title")
            detail = localized(key: "privateKeyValidation.publicKey.detail")
            kindTitle = keyKind.localizedTitle
        case .unrecognized:
            kind = .neutral
            systemIconName = "info.circle"
            title = localized(key: "privateKeyValidation.unrecognized.title")
            detail = localized(key: "privateKeyValidation.unrecognized.detail")
            kindTitle = localized(key: "privateKeyKind.other.title")
        case .empty:
            kind = .neutral
            systemIconName = "ellipsis.circle"
            title = localized(key: "privateKeyValidation.empty.title")
            detail = localized(key: "privateKeyValidation.empty.detail")
            kindTitle = ""
        }
    }

    private static func describe(
        _ problem: PrivateKeyProblem,
        of keyKind: PrivateKeyKind,
    ) -> (title: String, detail: String) {
        let kindName = keyKind.localizedTitleWithArticle
        return switch problem {
        case .outOfRange:
            (
                localized(key: "privateKeyValidation.outOfRange.title"),
                localized(key: "privateKeyValidation.outOfRange.detail.\(kindName)"),
            )
        case let .wrongLength(expected, actual) where keyKind == .hex:
            (
                localized(key: "privateKeyValidation.wrongLength.title"),
                localized(key: "privateKeyValidation.wrongLength.hex.detail.\(expected).\(actual)"),
            )
        case let .wrongLength(expected, actual):
            (
                localized(key: "privateKeyValidation.wrongLength.title"),
                localized(key: "privateKeyValidation.wrongLength.bytes.detail.\(kindName).\(expected).\(actual)"),
            )
        case .unknownVersion:
            (
                localized(key: "privateKeyValidation.unknownVersion.title"),
                localized(key: "privateKeyValidation.unknownVersion.detail.\(kindName)"),
            )
        case .unreadable:
            (
                localized(key: "privateKeyValidation.unreadable.title"),
                localized(key: "privateKeyValidation.unreadable.detail.\(kindName)"),
            )
        case .inconsistent:
            (
                localized(key: "privateKeyValidation.inconsistent.title"),
                localized(key: "privateKeyValidation.inconsistent.detail.\(kindName)"),
            )
        }
    }
}

// MARK: - Localization

extension PrivateKeyKind {
    public var localizedTitle: String {
        switch self {
        case .wif: localized(key: "privateKeyKind.wif.title")
        case .extendedKey: localized(key: "privateKeyKind.extendedKey.title")
        case .hex: localized(key: "privateKeyKind.hex.title")
        case .nostr: localized(key: "privateKeyKind.nostr.title")
        case .openPGP: localized(key: "privateKeyKind.openPGP.title")
        case .openSSH: localized(key: "privateKeyKind.openSSH.title")
        case .pem: localized(key: "privateKeyKind.pem.title")
        }
    }

    /// The kind as it reads in a sentence, such as "a WIF key".
    var localizedTitleWithArticle: String {
        switch self {
        case .wif: localized(key: "privateKeyKind.wif.withArticle")
        case .extendedKey: localized(key: "privateKeyKind.extendedKey.withArticle")
        case .hex: localized(key: "privateKeyKind.hex.withArticle")
        case .nostr: localized(key: "privateKeyKind.nostr.withArticle")
        case .openPGP: localized(key: "privateKeyKind.openPGP.withArticle")
        case .openSSH: localized(key: "privateKeyKind.openSSH.withArticle")
        case .pem: localized(key: "privateKeyKind.pem.withArticle")
        }
    }
}

extension PrivateKeyFormat {
    /// What Vault could tell about the key, such as "WIF · mainnet · compressed" or "OpenSSH · Ed25519".
    public var localizedDescription: String {
        let parts: [String?] = switch self {
        case let .wif(network, isCompressed):
            [
                kind.localizedTitle,
                network.localizedTitle,
                localized(key: isCompressed ? "privateKeyFormat.compressed" : "privateKeyFormat.uncompressed"),
            ]
        case let .extendedKey(version):
            [version.prefix, version.network.localizedTitle, version.script?.localizedTitle]
        case .hex:
            [kind.localizedTitle, localized(key: "privateKeyFormat.hex.length")]
        case .nostr:
            [kind.localizedTitle, "nsec"]
        case let .openPGP(algorithm):
            [kind.localizedTitle, algorithm?.localizedTitle]
        case let .openSSH(algorithm, isPassphraseProtected):
            [
                kind.localizedTitle,
                algorithm?.localizedTitle,
                isPassphraseProtected ? localized(key: "privateKeyFormat.passphraseProtected") : nil,
            ]
        case let .pem(encoding, algorithm, isEncrypted):
            [
                kind.localizedTitle,
                encoding.title,
                algorithm?.localizedTitle,
                isEncrypted ? localized(key: "privateKeyFormat.encrypted") : nil,
            ]
        }
        return parts.compactMap(\.self).joined(separator: " · ")
    }
}

extension WIFNetwork {
    var localizedTitle: String {
        switch self {
        case .mainnet: localized(key: "privateKeyFormat.network.mainnet")
        case .testnet: localized(key: "privateKeyFormat.network.testnet")
        }
    }
}

extension ExtendedKeyVersion.Network {
    var localizedTitle: String {
        switch self {
        case .bitcoin: localized(key: "privateKeyFormat.network.mainnet")
        case .bitcoinTestnet: localized(key: "privateKeyFormat.network.testnet")
        case .litecoin: localized(key: "privateKeyFormat.network.litecoin")
        case .litecoinTestnet: localized(key: "privateKeyFormat.network.litecoinTestnet")
        case .dogecoin: localized(key: "privateKeyFormat.network.dogecoin")
        }
    }
}

extension ExtendedKeyVersion.Script {
    var localizedTitle: String {
        switch self {
        case .nestedSegwit: localized(key: "privateKeyFormat.script.nestedSegwit")
        case .nativeSegwit: localized(key: "privateKeyFormat.script.nativeSegwit")
        case .nestedSegwitMultisig: localized(key: "privateKeyFormat.script.nestedSegwitMultisig")
        case .nativeSegwitMultisig: localized(key: "privateKeyFormat.script.nativeSegwitMultisig")
        }
    }
}

extension PEMKeyEncoding {
    /// The standard's name, which isn't translated.
    var title: String {
        switch self {
        case .pkcs1: "PKCS #1"
        case .sec1: "SEC 1"
        case .dsa: "DSA"
        case .pkcs8: "PKCS #8"
        }
    }
}

extension PrivateKeyAlgorithm {
    /// The algorithm's name, which isn't translated, apart from a security key's.
    var localizedTitle: String {
        switch self {
        case .rsa: "RSA"
        case .dsa: "DSA"
        case .elGamal: "ElGamal"
        case let .ec(curve): ["EC", curve?.title].compactMap(\.self).joined(separator: " ")
        case let .ecdsa(curve): ["ECDSA", curve?.title].compactMap(\.self).joined(separator: " ")
        case let .ecdh(curve): ["ECDH", curve?.title].compactMap(\.self).joined(separator: " ")
        case .eddsa: "EdDSA"
        case .ed25519: "Ed25519"
        case .ed448: "Ed448"
        case .x25519: "X25519"
        case .x448: "X448"
        case .ed25519SecurityKey: localized(key: "privateKeyFormat.securityKey.ed25519")
        case .ecdsaSecurityKey: localized(key: "privateKeyFormat.securityKey.ecdsa")
        }
    }
}

extension EllipticCurve {
    var title: String {
        switch self {
        case .secp256k1: "secp256k1"
        case .p256: "P-256"
        case .p384: "P-384"
        case .p521: "P-521"
        case .curve25519: "Curve25519"
        }
    }
}
