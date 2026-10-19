import Foundation
@testable import VaultCore

/// Keys for the private key tests: public test vectors for the single-line formats, and armored keys built here, with
/// made-up key material, in the layout each format's tool writes. No real key is kept in the repo, and none of these
/// has ever held anything.
enum PrivateKeyTestFixtures {
    // MARK: - Single-line vectors

    /// The private key in the Bitcoin wiki's WIF and Base58Check examples
    /// (https://en.bitcoin.it/wiki/Wallet_import_format).
    static let wikiKeyHex = "0C28FCA386C7A227600B2FE50B7CAE11EC86D3BF1FBE471BE89827E19D72AA1D"
    /// `wikiKeyHex` as a mainnet WIF key, uncompressed.
    static let wifUncompressed = "5HueCGU8rMjxEXxiPuD5BDku4MkFqeZyd4dZ1jvhTVqvbTLvyTJ"
    /// `wikiKeyHex` as a mainnet WIF key, compressed.
    static let wifCompressed = "KwdMAjGmerYanjeui5SHS7JkmpZvVipYvB2LJGU1ZxJwYvP98617"

    /// BIP32's test vector 1, the master key (https://github.com/bitcoin/bips/blob/master/bip-0032.mediawiki).
    static let bip32Vector1Master =
        "xprv9s21ZrQH143K3QTDL4LXw2F7HEK3wJUD2nW2nRk4stbPy6cq3jPPqjiChkVvvNKmPGJxWUtg6LnF5kejMRNNU3TGtRBeJgk33yuGBxrMPHi"
    /// Its public key.
    static let bip32Vector1MasterPublic =
        "xpub661MyMwAqRbcFtXgS5sYJABqqG9YLmC4Q1Rdap9gSE8NqtwybGhePY2gZ29ESFjqJoCu1Rupje8YtGqsefD265TMg7usUDFdp6W1EGMcet8"

    /// NIP-19's example private key (https://github.com/nostr-protocol/nips/blob/master/19.md).
    static let nip19PrivateKey = "nsec1vl029mgpspedva04g90vltkh6fvh240zqtv9k0t9af8935ke9laqsnlfe5"
    /// NIP-19's example public key.
    static let nip19PublicKey = "npub10elfcs4fr0l0r8af98jlmgdh9c8tcxjvz9qkw038js35mp4dma8qzvjptg"

    /// A Base58Check key with `payload`, its checksum worked out here, for keys BIP32 and WIF call invalid.
    static func base58Check(_ payload: [UInt8]) -> String {
        Base58Check.encode(payload)
    }

    /// A BIP32 extended key's 78 bytes: version, depth, parent fingerprint, child number, chain code, key.
    static func extendedKeyPayload(
        version: UInt32 = 0x0488_ADE4,
        depth: UInt8 = 0,
        parentFingerprint: [UInt8] = [0, 0, 0, 0],
        childNumber: [UInt8] = [0, 0, 0, 0],
        key: [UInt8] = [0x00] + Array(repeating: 0x11, count: 32),
    ) -> [UInt8] {
        withUnsafeBytes(of: version.bigEndian, Array.init) + [depth] + parentFingerprint + childNumber
            + Array(repeating: 0x22, count: 32) + key
    }

    // MARK: - Armor

    /// `data` armored with `label`, as PEM and OpenSSH write it: 64 characters to a line (OpenSSH uses 70).
    static func armored(
        _ label: String,
        data: [UInt8],
        lineLength: Int = 64,
        headers: [String] = [],
        checksumLine: String? = nil,
    ) -> String {
        let base64 = Data(data).base64EncodedString()
        var lines = ["-----BEGIN \(label)-----"]
        if headers.isNotEmpty || checksumLine != nil {
            // OpenPGP's armor, and a legacy encrypted PEM key, have headers and a blank line before the Base64.
            lines += headers + [""]
        }
        var index = base64.startIndex
        while index < base64.endIndex {
            let end = base64.index(index, offsetBy: lineLength, limitedBy: base64.endIndex) ?? base64.endIndex
            lines.append(String(base64[index ..< end]))
            index = end
        }
        if let checksumLine {
            lines.append(checksumLine)
        }
        lines.append("-----END \(label)-----")
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - OpenSSH

    /// An `openssh-key-v1` key, as PROTOCOL.key lays it out, with made-up key material.
    static func openSSHKey(
        keyType: String = "ssh-ed25519",
        cipher: String = "none",
        checks: (UInt32, UInt32) = (0x1234_5678, 0x1234_5678),
    ) -> String {
        let publicKey = sshString(keyType) + sshString(Array(repeating: 0xAB, count: 32))
        var privateSection = sshUInt32(checks.0) + sshUInt32(checks.1)
        privateSection += sshString(keyType) + sshString(Array(repeating: 0xAB, count: 32))
        privateSection += sshString(Array(repeating: 0xCD, count: 64)) + sshString("")
        privateSection += [1, 2, 3, 4, 5, 6, 7].prefix((8 - privateSection.count % 8) % 8)
        let isEncrypted = cipher != "none"
        var data = Array("openssh-key-v1".utf8) + [0]
        data += sshString(cipher) + sshString(isEncrypted ? "bcrypt" : "none")
        data += sshString(isEncrypted ? sshString(Array(repeating: 0x5A, count: 16)) + sshUInt32(16) : [])
        data += sshUInt32(1) + sshString(publicKey)
        // Encrypted, the private section is just bytes, as it would look.
        data += sshString(isEncrypted ? Array(repeating: 0x77, count: privateSection.count) : privateSection)
        return armored("OPENSSH PRIVATE KEY", data: data, lineLength: 70)
    }

    private static func sshUInt32(_ value: UInt32) -> [UInt8] {
        withUnsafeBytes(of: value.bigEndian, Array.init)
    }

    private static func sshString(_ bytes: [UInt8]) -> [UInt8] {
        sshUInt32(UInt32(bytes.count)) + bytes
    }

    private static func sshString(_ text: String) -> [UInt8] {
        sshString(Array(text.utf8))
    }

    // MARK: - OpenPGP

    /// OpenPGP's legacy Ed25519 curve OID.
    static let ed25519LegacyOID: [UInt8] = [0x2B, 0x06, 0x01, 0x04, 0x01, 0xDA, 0x47, 0x0F, 0x01]

    /// A version 4 secret key packet (tag 5) for `algorithm`, as GnuPG writes one: in the old packet format, with the
    /// curve's OID for an elliptic curve key, then made-up key material.
    static func openPGPSecretKeyPacket(algorithm: UInt8 = 22, tag: UInt8 = 5, curveOID: [UInt8]? = ed25519LegacyOID)
        -> [UInt8]
    {
        var body: [UInt8] = [4, 0x6A, 0xD5, 0xEA, 0x0E, algorithm]
        if let curveOID {
            body += [UInt8(curveOID.count)] + curveOID
        }
        body += Array(repeating: 0x42, count: 40)
        return [0x80 | (tag << 2)] + [UInt8(body.count)] + body
    }

    /// `packet` in an OpenPGP armor, with its CRC-24, or `checksum` in its place.
    static func openPGPKey(
        packet: [UInt8] = openPGPSecretKeyPacket(),
        label: String = "PGP PRIVATE KEY BLOCK",
        checksum: UInt32? = nil,
        includesChecksum: Bool = true,
    ) -> String {
        let crc = checksum ?? CRC24.checksum(packet)
        let crcBytes: [UInt8] = [UInt8((crc >> 16) & 0xFF), UInt8((crc >> 8) & 0xFF), UInt8(crc & 0xFF)]
        let checksumLine = includesChecksum ? "=" + Data(crcBytes).base64EncodedString() : nil
        return armored(label, data: packet, headers: ["Comment: Made for Vault's tests"], checksumLine: checksumLine)
    }

    // MARK: - PEM

    /// PKCS #8 PrivateKeyInfo for Ed25519 (RFC 8410, section 7), with made-up key material.
    static let pkcs8Ed25519: [UInt8] = [
        0x30, 0x2E, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03, 0x2B, 0x65, 0x70, 0x04, 0x22, 0x04, 0x20,
    ] + Array(repeating: 0x31, count: 32)

    /// PKCS #8 PrivateKeyInfo for an EC key on secp256k1: the version, the algorithm with the curve, and the key.
    static let pkcs8Secp256k1: [UInt8] = [
        0x30, 0x1F, 0x02, 0x01, 0x00,
        0x30, 0x10, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01, 0x06, 0x05, 0x2B, 0x81, 0x04, 0x00, 0x0A,
        0x04, 0x08,
    ] + Array(repeating: 0x32, count: 8)

    /// SEC 1 ECPrivateKey (RFC 5915) on secp256k1: the version, the key and the curve.
    static let sec1Secp256k1: [UInt8] = [0x30, 0x2E, 0x02, 0x01, 0x01, 0x04, 0x20]
        + Array(repeating: 0x33, count: 32)
        + [0xA0, 0x07, 0x06, 0x05, 0x2B, 0x81, 0x04, 0x00, 0x0A]

    /// The start of a PKCS #1 RSAPrivateKey: a SEQUENCE starting with its version.
    static let pkcs1RSA: [UInt8] = [0x30, 0x06, 0x02, 0x01, 0x00, 0x02, 0x01, 0x05]

    /// PKCS #8 EncryptedPrivateKeyInfo: how it's encrypted, then the encrypted key.
    static let encryptedPKCS8: [UInt8] = [
        0x30, 0x1D,
        0x30, 0x0B, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x05, 0x0D,
        0x04, 0x0E,
    ] + Array(repeating: 0x34, count: 14)
}
