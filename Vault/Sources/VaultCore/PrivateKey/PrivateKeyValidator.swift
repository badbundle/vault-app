import Foundation
import FoundationExtensions

/// Recognizes the format of text entered as a private key, and checks it against that format's checksum, where it has
/// one, and its rules.
///
/// Like `RecoveryPhraseValidator`, this only ever informs: a key that doesn't validate can still be saved, and anything
/// Vault doesn't recognize is kept as other text. It never derives anything from the key, such as a public key or an
/// address.
public enum PrivateKeyValidator {
    public static func validate(_ text: String) -> PrivateKeyValidation {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isNotEmpty else { return .init(status: .empty) }
        if ArmoredBlock.label(in: trimmed) != nil {
            return .init(status: ArmoredPrivateKeys.validate(trimmed))
        }
        if isOpenSSHPublicKey(trimmed) {
            return .init(status: .publicKey(.openSSH))
        }

        // A single-line key copied over more than one line, or written in groups, is the same key once the
        // whitespace is gone.
        let compact = String(trimmed.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) })
        let status = validateSingleLine(compact)
        let isCanonicalDifferent = compact != trimmed
        if case .valid = status, isCanonicalDifferent {
            return .init(status: status, canonicalKey: compact)
        }
        return .init(status: status)
    }

    /// An OpenSSH public key line, like `ssh-ed25519 AAAA… comment`, as it's written to a `.pub` file.
    private static func isOpenSSHPublicKey(_ text: String) -> Bool {
        let prefixes = ["ssh-", "ecdsa-sha2-", "sk-ssh-", "sk-ecdsa-"]
        guard prefixes.contains(where: text.hasPrefix) else { return false }
        let parts = text.split(whereSeparator: \.isWhitespace)
        return parts.count >= 2 && parts[1].hasPrefix("AAAA")
    }

    private static func validateSingleLine(_ key: String) -> PrivateKeyValidation.Status {
        let lowercased = key.lowercased()
        if lowercased.hasPrefix("nsec1") || lowercased.hasPrefix("npub1") {
            return nostr(key)
        }
        if let hex = hex(key) {
            return hex
        }
        if Base58Check.isBase58(key) {
            return base58Check(key)
        }
        return .unrecognized
    }

    // MARK: - Nostr

    /// NIP-19: `nsec` and 32 bytes, bech32 encoded. A key for BIP-340 signatures, so from 1 to `n - 1`.
    private static func nostr(_ key: String) -> PrivateKeyValidation.Status {
        switch Bech32.decode(key) {
        case let .valid(humanReadablePart, data):
            guard humanReadablePart == "nsec" else {
                return humanReadablePart == "npub" ? .publicKey(.nostr) : .unrecognized
            }
            guard data.count == 32 else { return .malformed(.nostr, .wrongLength(expected: 32, actual: data.count)) }
            guard Secp256k1.isValidPrivateKey(data) else { return .malformed(.nostr, .outOfRange) }
            return .valid(.nostr)
        case let .invalidChecksum(humanReadablePart):
            return humanReadablePart == "npub" ? .publicKey(.nostr) : .invalidChecksum(.nostr)
        case .invalid:
            return .malformed(.nostr, .unreadable)
        }
    }

    // MARK: - Hex

    /// 32 bytes as 64 hexadecimal digits, with or without `0x`. Something a digit or two away from that length is
    /// most likely a key mistyped, so it says so; anything else of hexadecimal digits isn't taken as a key.
    private static func hex(_ key: String) -> PrivateKeyValidation.Status? {
        let hasPrefix = key.hasPrefix("0x") || key.hasPrefix("0X")
        let digits = hasPrefix ? key.dropFirst(2) : Substring(key)
        guard digits.isNotEmpty, digits.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        guard digits.count == 64 else {
            guard hasPrefix || abs(digits.count - 64) <= 2 else { return nil }
            return .malformed(.hex, .wrongLength(expected: 64, actual: digits.count))
        }
        var bytes = [UInt8]()
        var index = digits.startIndex
        while index < digits.endIndex {
            let next = digits.index(index, offsetBy: 2)
            guard let byte = UInt8(digits[index ..< next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return Secp256k1.isValidPrivateKey(bytes) ? .valid(.hex) : .malformed(.hex, .outOfRange)
    }

    // MARK: - Base58Check

    private static func base58Check(_ key: String) -> PrivateKeyValidation.Status {
        switch Base58Check.decode(key) {
        case let .valid(payload):
            switch payload.count {
            case 33, 34: wif(payload)
            case 78: extendedKey(payload)
            default: .unrecognized
            }
        case .invalidChecksum:
            mistypedBase58CheckKey(key)
        case .notBase58:
            .unrecognized
        }
    }

    /// The version byte, the 32-byte key, then `0x01` if its public key is compressed.
    private static func wif(_ payload: [UInt8]) -> PrivateKeyValidation.Status {
        guard let network = WIFNetwork(versionByte: payload[0]) else { return .malformed(.wif, .unknownVersion) }
        let isCompressed = payload.count == 34
        if isCompressed, payload[33] != 0x01 {
            return .malformed(.wif, .unreadable)
        }
        guard Secp256k1.isValidPrivateKey(payload[1 ..< 33]) else { return .malformed(.wif, .outOfRange) }
        return .valid(.wif(network: network, isCompressed: isCompressed))
    }

    /// BIP32's serialization: version (4 bytes), depth (1), parent fingerprint (4), child number (4), chain code
    /// (32), then `0x00` and the 32-byte private key, or a 33-byte public key.
    private static func extendedKey(_ payload: [UInt8]) -> PrivateKeyValidation.Status {
        let versionBytes = payload[0 ..< 4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        if ExtendedKeyVersion.publicKeyVersions[versionBytes] != nil {
            return .publicKey(.extendedKey)
        }
        guard let version = ExtendedKeyVersion.privateKeyVersions.first(where: { $0.versionBytes == versionBytes })
        else { return .malformed(.extendedKey, .unknownVersion) }
        let depth = payload[4]
        let parentFingerprint = payload[5 ..< 9]
        let childNumber = payload[9 ..< 13]
        // BIP32's invalid test vectors: a private version holding a public key, and a master key (depth 0) with a
        // parent or an index.
        guard payload[45] == 0x00 else { return .malformed(.extendedKey, .inconsistent) }
        if depth == 0, parentFingerprint.contains(where: { $0 != 0 }) || childNumber.contains(where: { $0 != 0 }) {
            return .malformed(.extendedKey, .inconsistent)
        }
        guard Secp256k1.isValidPrivateKey(payload[46 ..< 78]) else { return .malformed(.extendedKey, .outOfRange) }
        return .valid(.extendedKey(version))
    }

    /// Base58 that's the length of a WIF key, or starts like an extended key, but doesn't check: most likely a
    /// character mistyped.
    private static func mistypedBase58CheckKey(_ key: String) -> PrivateKeyValidation.Status {
        let prefix = String(key.prefix(4))
        if (110 ... 112).contains(key.count) {
            if ExtendedKeyVersion.privateKeyVersions.contains(where: { $0.prefix == prefix }) {
                return .invalidChecksum(.extendedKey)
            }
            if ExtendedKeyVersion.publicKeyVersions.values.contains(prefix) {
                return .publicKey(.extendedKey)
            }
        }
        // Uncompressed keys start with 5 (mainnet) or 9 (testnet), compressed ones with K or L (mainnet) or c.
        if key.count == 51, let first = key.first, "59".contains(first) {
            return .invalidChecksum(.wif)
        }
        if key.count == 52, let first = key.first, "KLc".contains(first) {
            return .invalidChecksum(.wif)
        }
        return .unrecognized
    }
}
