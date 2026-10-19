import Foundation

/// A kind of private key that Vault recognizes.
public enum PrivateKeyKind: Equatable, Hashable, CaseIterable, Sendable {
    /// Wallet Import Format: a single secp256k1 key, Base58Check encoded.
    ///
    /// https://en.bitcoin.it/wiki/Wallet_import_format
    case wif
    /// A BIP32 extended private key, such as an xprv, or one of the SLIP-132 versions of it (yprv, zprv, tprv and
    /// others), Base58Check encoded.
    ///
    /// https://github.com/bitcoin/bips/blob/master/bip-0032.mediawiki,
    /// https://github.com/satoshilabs/slips/blob/master/slip-0132.md
    case extendedKey
    /// A raw secp256k1 private key: 32 bytes as 64 hexadecimal digits, optionally starting with `0x`.
    case hex
    /// A Nostr private key, `nsec`, bech32 encoded.
    ///
    /// https://github.com/nostr-protocol/nips/blob/master/19.md
    case nostr
    /// An ASCII armored OpenPGP private key block (`-----BEGIN PGP PRIVATE KEY BLOCK-----`).
    ///
    /// https://www.rfc-editor.org/rfc/rfc9580
    case openPGP
    /// An OpenSSH private key (`-----BEGIN OPENSSH PRIVATE KEY-----`), as `ssh-keygen` writes it.
    ///
    /// https://github.com/openssh/openssh-portable/blob/master/PROTOCOL.key
    case openSSH
    /// A PEM private key: PKCS #1 (`RSA PRIVATE KEY`), SEC 1 (`EC PRIVATE KEY`), OpenSSL's DSA (`DSA PRIVATE KEY`), or
    /// PKCS #8 (`PRIVATE KEY` or `ENCRYPTED PRIVATE KEY`).
    ///
    /// https://www.rfc-editor.org/rfc/rfc7468
    case pem
}

/// A private key Vault has recognized, with what it could tell about it from the key's own encoding. Nothing is
/// derived from it.
public enum PrivateKeyFormat: Equatable, Hashable, Sendable {
    case wif(network: WIFNetwork, isCompressed: Bool)
    case extendedKey(ExtendedKeyVersion)
    case hex
    case nostr
    case openPGP(algorithm: PrivateKeyAlgorithm?)
    case openSSH(algorithm: PrivateKeyAlgorithm?, isPassphraseProtected: Bool)
    case pem(PEMKeyEncoding, algorithm: PrivateKeyAlgorithm?, isEncrypted: Bool)

    public var kind: PrivateKeyKind {
        switch self {
        case .wif: .wif
        case .extendedKey: .extendedKey
        case .hex: .hex
        case .nostr: .nostr
        case .openPGP: .openPGP
        case .openSSH: .openSSH
        case .pem: .pem
        }
    }
}

/// The network a WIF key is for, from its version byte.
public enum WIFNetwork: Equatable, Hashable, Sendable {
    /// Version byte `0x80`.
    case mainnet
    /// Version byte `0xEF`.
    case testnet

    init?(versionByte: UInt8) {
        switch versionByte {
        case 0x80: self = .mainnet
        case 0xEF: self = .testnet
        default: return nil
        }
    }
}

/// The version of an extended private key, from SLIP-132's registry: what its first four letters say about it.
public struct ExtendedKeyVersion: Equatable, Hashable, Sendable {
    public enum Network: Equatable, Hashable, Sendable {
        case bitcoin
        case bitcoinTestnet
        case litecoin
        case litecoinTestnet
        case dogecoin
    }

    /// The kind of address the version says the key's wallet uses, where it says.
    public enum Script: Equatable, Hashable, Sendable {
        /// P2WPKH nested in P2SH (BIP49).
        case nestedSegwit
        /// P2WPKH (BIP84).
        case nativeSegwit
        /// Multi-signature P2WSH nested in P2SH.
        case nestedSegwitMultisig
        /// Multi-signature P2WSH.
        case nativeSegwitMultisig
    }

    /// The version bytes, big-endian, that start the key's data.
    public let versionBytes: UInt32
    /// The four letters the encoded key starts with, such as "xprv".
    public let prefix: String
    public let network: Network
    /// `nil` for the original BIP32 versions, which say nothing about the script (P2PKH or P2SH).
    public let script: Script?

    /// Every version of an extended private key that SLIP-132 registers for Bitcoin, Litecoin and Dogecoin.
    public static let privateKeyVersions: [ExtendedKeyVersion] = [
        .init(versionBytes: 0x0488_ADE4, prefix: "xprv", network: .bitcoin, script: nil),
        .init(versionBytes: 0x049D_7878, prefix: "yprv", network: .bitcoin, script: .nestedSegwit),
        .init(versionBytes: 0x04B2_430C, prefix: "zprv", network: .bitcoin, script: .nativeSegwit),
        .init(versionBytes: 0x0295_B005, prefix: "Yprv", network: .bitcoin, script: .nestedSegwitMultisig),
        .init(versionBytes: 0x02AA_7A99, prefix: "Zprv", network: .bitcoin, script: .nativeSegwitMultisig),
        .init(versionBytes: 0x0435_8394, prefix: "tprv", network: .bitcoinTestnet, script: nil),
        .init(versionBytes: 0x044A_4E28, prefix: "uprv", network: .bitcoinTestnet, script: .nestedSegwit),
        .init(versionBytes: 0x045F_18BC, prefix: "vprv", network: .bitcoinTestnet, script: .nativeSegwit),
        .init(versionBytes: 0x0242_85B5, prefix: "Uprv", network: .bitcoinTestnet, script: .nestedSegwitMultisig),
        .init(versionBytes: 0x0257_5048, prefix: "Vprv", network: .bitcoinTestnet, script: .nativeSegwitMultisig),
        .init(versionBytes: 0x019D_9CFE, prefix: "Ltpv", network: .litecoin, script: nil),
        .init(versionBytes: 0x01B2_6792, prefix: "Mtpv", network: .litecoin, script: .nestedSegwit),
        .init(versionBytes: 0x0436_EF7D, prefix: "ttpv", network: .litecoinTestnet, script: nil),
        .init(versionBytes: 0x02FA_C398, prefix: "dgpv", network: .dogecoin, script: nil),
    ]

    /// The public key versions that go with `privateKeyVersions`, to recognize a public key entered by mistake.
    static let publicKeyVersions: [UInt32: String] = [
        0x0488_B21E: "xpub", 0x049D_7CB2: "ypub", 0x04B2_4746: "zpub", 0x0295_B43F: "Ypub", 0x02AA_7ED3: "Zpub",
        0x0435_87CF: "tpub", 0x044A_5262: "upub", 0x045F_1CF6: "vpub", 0x0242_89EF: "Upub", 0x0257_5483: "Vpub",
        0x019D_A462: "Ltub", 0x01B2_6EF6: "Mtub", 0x0436_F6E1: "ttub", 0x02FA_CAFD: "dgub",
    ]
}

/// What kind of key a PGP, SSH or PEM private key is, as far as its encoding says without decrypting or deriving
/// anything.
public enum PrivateKeyAlgorithm: Equatable, Hashable, Sendable {
    case rsa
    case dsa
    case elGamal
    /// An elliptic curve key whose use isn't stated, as a PEM `EC PRIVATE KEY` is.
    case ec(EllipticCurve?)
    case ecdsa(EllipticCurve?)
    case ecdh(EllipticCurve?)
    /// OpenPGP's legacy EdDSA, on a curve Vault doesn't name.
    case eddsa
    case ed25519
    case ed448
    case x25519
    case x448
    /// An Ed25519 key on a FIDO security key (`sk-ssh-ed25519@openssh.com`).
    case ed25519SecurityKey
    /// An ECDSA P-256 key on a FIDO security key (`sk-ecdsa-sha2-nistp256@openssh.com`).
    case ecdsaSecurityKey
}

public enum EllipticCurve: Equatable, Hashable, Sendable {
    case secp256k1
    case p256
    case p384
    case p521
    case curve25519
}

/// How a PEM private key's DER is structured, from its label.
public enum PEMKeyEncoding: Equatable, Hashable, Sendable {
    /// `RSA PRIVATE KEY`.
    case pkcs1
    /// `EC PRIVATE KEY`.
    case sec1
    /// `DSA PRIVATE KEY`, OpenSSL's own.
    case dsa
    /// `PRIVATE KEY`, or `ENCRYPTED PRIVATE KEY`.
    case pkcs8
}

/// Why a key Vault recognized can't be a usable private key.
public enum PrivateKeyProblem: Equatable, Hashable, Sendable {
    /// The key is zero, or not less than the order of secp256k1 (`n`), so isn't a valid secp256k1 private key.
    case outOfRange
    /// The key isn't the length its format needs, in bytes (or, for hex, in digits).
    case wrongLength(expected: Int, actual: Int)
    /// The checksum matches, but Vault doesn't know the version the key says it is.
    case unknownVersion
    /// The text can't be read as the format it looks like: it isn't valid Base64, an armor line is missing, or what's
    /// inside isn't what the format holds.
    case unreadable
    /// Parts of the key that must agree don't: an extended private key with a public key in it, or at depth 0 with a
    /// parent; an OpenSSH key whose check numbers differ.
    case inconsistent
}

/// The result of checking text entered as a private key.
public struct PrivateKeyValidation: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        /// Nothing has been entered.
        case empty
        /// Recognized, with its checksum matching where it has one.
        case valid(PrivateKeyFormat)
        /// It looks like this kind of key, but its checksum doesn't match: a character is likely mistyped.
        case invalidChecksum(PrivateKeyKind)
        /// It's this kind of key, but can't be a usable one.
        case malformed(PrivateKeyKind, PrivateKeyProblem)
        /// It's a public key of this kind, which can't sign or spend: most likely copied instead of the private key.
        case publicKey(PrivateKeyKind)
        /// Not a format Vault recognizes. It can still be saved, unchecked, as other text.
        case unrecognized
    }

    public var status: Status
    /// For a single-line key that's only valid with the whitespace inside it removed (such as one split over two
    /// lines), the key without it: the form a wallet will accept.
    public var canonicalKey: String?

    public init(status: Status, canonicalKey: String? = nil) {
        self.status = status
        self.canonicalKey = canonicalKey
    }

    public var isValid: Bool {
        if case .valid = status {
            true
        } else {
            false
        }
    }

    public var format: PrivateKeyFormat? {
        if case let .valid(format) = status {
            format
        } else {
            nil
        }
    }
}
