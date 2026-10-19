import Foundation
import Testing
@testable import VaultCore

struct PrivateKeyValidatorTests {
    private typealias Fixtures = PrivateKeyTestFixtures

    // MARK: - Nothing, and anything else

    @Test(arguments: ["", " ", "\n\t  \n"])
    func validate_blankIsEmpty(text: String) {
        #expect(PrivateKeyValidator.validate(text).status == .empty)
    }

    /// Anything Vault doesn't recognize is kept as other text, unchecked.
    @Test(arguments: [
        "hello world",
        "correct horse battery staple",
        "🔑 my key",
        "1BoatSLRHtKNngkdXEeobR76b4LvkhAfiV", // An address, not a key.
        "-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----",
        String(repeating: "ab", count: 50), // Hex, but not near a key's length.
    ])
    func validate_anythingElseIsUnrecognized(text: String) {
        #expect(PrivateKeyValidator.validate(text).status == .unrecognized)
    }

    // MARK: - WIF

    @Test
    func validate_wifUncompressed() {
        let result = PrivateKeyValidator.validate(Fixtures.wifUncompressed)

        #expect(result.status == .valid(.wif(network: .mainnet, isCompressed: false)))
        #expect(result.canonicalKey == nil)
    }

    @Test
    func validate_wifCompressed() {
        #expect(
            PrivateKeyValidator.validate(Fixtures.wifCompressed).status
                == .valid(.wif(network: .mainnet, isCompressed: true)),
        )
    }

    @Test
    func validate_wifTestnet() throws {
        let key = try hexBytes(Fixtures.wikiKeyHex)

        let result = PrivateKeyValidator.validate(Fixtures.base58Check([0xEF] + key + [0x01]))

        #expect(result.status == .valid(.wif(network: .testnet, isCompressed: true)))
    }

    /// A character mistyped as another Base58 character: the checksum catches it.
    @Test(arguments: [
        "5HueCGU8rMjxEXxiPuD5BDku4MkFqeZyd4dZ1jvhTVqvbTLvyTK",
        "KwdMAjGmerYanjeui5SHS7JkmpZvVipYvB2LJGU1ZxJwYvP98618",
        "KwdMAjGmerYanjeui5SHS7JkmpZvVipYvB2LJGU1ZxJwYvP98716",
    ])
    func validate_wifWithAMistypedCharacterHasAnInvalidChecksum(key: String) {
        #expect(PrivateKeyValidator.validate(key).status == .invalidChecksum(.wif))
    }

    @Test
    func validate_wifOfZeroIsOutOfRange() {
        let key = Fixtures.base58Check([0x80] + Array(repeating: 0, count: 32))

        #expect(PrivateKeyValidator.validate(key).status == .malformed(.wif, .outOfRange))
    }

    @Test
    func validate_wifOfTheCurveOrderIsOutOfRange() {
        let key = Fixtures.base58Check([0x80] + Secp256k1.order + [0x01])

        #expect(PrivateKeyValidator.validate(key).status == .malformed(.wif, .outOfRange))
    }

    @Test
    func validate_wifWithAnUnknownVersionSaysSo() throws {
        let key = try Fixtures.base58Check([0x81] + hexBytes(Fixtures.wikiKeyHex))

        #expect(PrivateKeyValidator.validate(key).status == .malformed(.wif, .unknownVersion))
    }

    @Test
    func validate_wifWithAWrongCompressionFlagIsUnreadable() throws {
        let key = try Fixtures.base58Check([0x80] + hexBytes(Fixtures.wikiKeyHex) + [0x02])

        #expect(PrivateKeyValidator.validate(key).status == .malformed(.wif, .unreadable))
    }

    /// Copied over two lines, or with spaces in it, a key is still the same key, and is saved without them.
    @Test(arguments: [
        "KwdMAjGmerYanjeui5SHS7Jkmp ZvVipYvB2LJGU1ZxJwYvP98617",
        "KwdMAjGmerYanjeui5SHS7Jkmp\nZvVipYvB2LJGU1ZxJwYvP98617",
    ])
    func validate_whitespaceInsideASingleLineKeyIsRemoved(text: String) {
        let result = PrivateKeyValidator.validate(text)

        #expect(result.status == .valid(.wif(network: .mainnet, isCompressed: true)))
        #expect(result.canonicalKey == Fixtures.wifCompressed)
    }

    /// Whitespace around a key is trimmed as it's saved, so it isn't a different form of the key.
    @Test
    func validate_whitespaceAroundAKeyIsValidAsItIs() {
        let result = PrivateKeyValidator.validate("  \(Fixtures.wifCompressed)\n")

        #expect(result.status == .valid(.wif(network: .mainnet, isCompressed: true)))
        #expect(result.canonicalKey == nil)
    }

    // MARK: - Extended keys

    @Test
    func validate_bip32MasterKey() throws {
        let result = PrivateKeyValidator.validate(Fixtures.bip32Vector1Master)

        let version = try #require(ExtendedKeyVersion.privateKeyVersions.first { $0.prefix == "xprv" })
        #expect(result.status == .valid(.extendedKey(version)))
    }

    /// Every SLIP-132 version is recognized by its version bytes, which give the letters it starts with.
    @Test(arguments: ExtendedKeyVersion.privateKeyVersions)
    func validate_everySLIP132PrivateVersion(version: ExtendedKeyVersion) {
        let key = Fixtures.base58Check(Fixtures.extendedKeyPayload(version: version.versionBytes))

        #expect(key.hasPrefix(version.prefix))
        #expect(PrivateKeyValidator.validate(key).status == .valid(.extendedKey(version)))
    }

    @Test
    func validate_extendedKeyWithAMistypedCharacterHasAnInvalidChecksum() {
        var key = Fixtures.bip32Vector1Master
        key.removeLast()
        key.append("L")

        #expect(PrivateKeyValidator.validate(key).status == .invalidChecksum(.extendedKey))
    }

    @Test(arguments: [UInt32(0x0488_B21E), 0x04B2_4746, 0x0435_87CF])
    func validate_extendedPublicKeyIsAPublicKey(version: UInt32) {
        let key = Fixtures.base58Check(Fixtures.extendedKeyPayload(
            version: version,
            key: [0x02] + Array(repeating: 0x11, count: 32),
        ))

        #expect(PrivateKeyValidator.validate(key).status == .publicKey(.extendedKey))
    }

    @Test
    func validate_bip32MasterPublicKeyIsAPublicKey() {
        #expect(PrivateKeyValidator.validate(Fixtures.bip32Vector1MasterPublic).status == .publicKey(.extendedKey))
    }

    /// BIP32's test vector 5, of keys that must be rejected.
    @Test(arguments: [
        // A private version with a public key.
        (
            "xprv9s21ZrQH143K24Mfq5zL5MhWK9hUhhGbd45hLXo2Pq2oqzMMo63oStZzFGTQQD3dC4H2D5GBj7vWvSQaaBv5cxi9gafk7NF3pnBju6dwKvH",
            PrivateKeyProblem.inconsistent,
        ),
        // Depth 0 with a parent fingerprint.
        (
            "xprv9s2SPatNQ9Vc6GTbVMFPFo7jsaZySyzk7L8n2uqKXJen3KUmvQNTuLh3fhZMBoG3G4ZW1N2kZuHEPY53qmbZzCHshoQnNf4GvELZfqTUrcv",
            .inconsistent,
        ),
        // Depth 0 with a child number.
        (
            "xprv9s21ZrQH4r4TsiLvyLXqM9P7k1K3EYhA1kkD6xuquB5i39AU8KF42acDyL3qsDbU9NmZn6MsGSUYZEsuoePmjzsB3eFKSUEh3Gu1N3cqVUN",
            .inconsistent,
        ),
        // An unknown version.
        (
            "DMwo58pR1QLEFihHiXPVykYB6fJmsTeHvyTp7hRThAtCX8CvYzgPcn8XnmdfHGMQzT7ayAmfo4z3gY5KfbrZWZ6St24UVf2Qgo6oujFktLHdHY4",
            .unknownVersion,
        ),
        // A key of 0.
        (
            "xprv9s21ZrQH143K24Mfq5zL5MhWK9hUhhGbd45hLXo2Pq2oqzMMo63oStZzF93Y5wvzdUayhgkkFoicQZcP3y52uPPxFnfoLZB21Teqt1VvEHx",
            .outOfRange,
        ),
        // A key of n.
        (
            "xprv9s21ZrQH143K24Mfq5zL5MhWK9hUhhGbd45hLXo2Pq2oqzMMo63oStZzFAzHGBP2UuGCqWLTAPLcMtD5SDKr24z3aiUvKr9bJpdrcLg1y3G",
            .outOfRange,
        ),
    ])
    func validate_bip32InvalidVectors(key: String, problem: PrivateKeyProblem) {
        #expect(PrivateKeyValidator.validate(key).status == .malformed(.extendedKey, problem))
    }

    @Test
    func validate_bip32InvalidChecksumVector() {
        let key =
            "xprv9s21ZrQH143K3QTDL4LXw2F7HEK3wJUD2nW2nRk4stbPy6cq3jPPqjiChkVvvNKmPGJxWUtg6LnF5kejMRNNU3TGtRBeJgk33yuGBxrMPHL"

        #expect(PrivateKeyValidator.validate(key).status == .invalidChecksum(.extendedKey))
    }

    // MARK: - Hex

    @Test(arguments: [
        PrivateKeyTestFixtures.wikiKeyHex,
        PrivateKeyTestFixtures.wikiKeyHex.lowercased(),
        "0x" + PrivateKeyTestFixtures.wikiKeyHex.lowercased(),
        "0X" + PrivateKeyTestFixtures.wikiKeyHex,
        // n - 1, the largest key.
        "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364140",
        "0000000000000000000000000000000000000000000000000000000000000001",
    ])
    func validate_hexKeysInRange(key: String) {
        #expect(PrivateKeyValidator.validate(key).status == .valid(.hex))
    }

    @Test(arguments: [
        "0000000000000000000000000000000000000000000000000000000000000000",
        // n, and above it.
        "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141",
        "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF",
    ])
    func validate_hexKeysOutOfRange(key: String) {
        #expect(PrivateKeyValidator.validate(key).status == .malformed(.hex, .outOfRange))
    }

    @Test
    func validate_hexADigitShortIsTheWrongLength() {
        let key = String(Fixtures.wikiKeyHex.dropLast())

        #expect(PrivateKeyValidator.validate(key).status == .malformed(.hex, .wrongLength(expected: 64, actual: 63)))
    }

    @Test
    func validate_hexWithAPrefixIsTheWrongLengthWhateverItsLength() {
        #expect(PrivateKeyValidator.validate("0x1234").status == .malformed(
            .hex,
            .wrongLength(expected: 64, actual: 4),
        ))
    }

    @Test
    func validate_hexInGroupsIsTheSameKey() {
        let grouped = stride(from: 0, to: 64, by: 8).map { offset in
            let start = Fixtures.wikiKeyHex.index(Fixtures.wikiKeyHex.startIndex, offsetBy: offset)
            return String(Fixtures.wikiKeyHex[start ..< Fixtures.wikiKeyHex.index(start, offsetBy: 8)])
        }.joined(separator: " ")

        let result = PrivateKeyValidator.validate(grouped)

        #expect(result.status == .valid(.hex))
        #expect(result.canonicalKey == Fixtures.wikiKeyHex)
    }

    // MARK: - Nostr

    @Test
    func validate_nip19PrivateKey() {
        #expect(PrivateKeyValidator.validate(Fixtures.nip19PrivateKey).status == .valid(.nostr))
    }

    @Test
    func validate_nsecInCapitalsIsValid() {
        #expect(PrivateKeyValidator.validate(Fixtures.nip19PrivateKey.uppercased()).status == .valid(.nostr))
    }

    @Test(arguments: [
        "nsec1vl029mgpspedva04g90vltkh6fvh240zqtv9k0t9af8935ke9laqsnlfe6",
        "nsec1vl029mgpspedva04g90vltkh6fvh240zqtv9k0t9af8935ke9laqsnlef5",
    ])
    func validate_nsecWithAMistypedCharacterHasAnInvalidChecksum(key: String) {
        #expect(PrivateKeyValidator.validate(key).status == .invalidChecksum(.nostr))
    }

    /// Bech32 never mixes capitals and lower case.
    @Test
    func validate_nsecInMixedCaseIsUnreadable() {
        let key = "nsec1VL029mgpspedva04g90vltkh6fvh240zqtv9k0t9af8935ke9laqsnlfe5"

        #expect(PrivateKeyValidator.validate(key).status == .malformed(.nostr, .unreadable))
    }

    @Test
    func validate_nsecOfZeroIsOutOfRange() {
        let key = Bech32.encode(humanReadablePart: "nsec", data: Array(repeating: 0, count: 32))

        #expect(PrivateKeyValidator.validate(key).status == .malformed(.nostr, .outOfRange))
    }

    @Test
    func validate_nsecOfTheWrongLength() {
        let key = Bech32.encode(humanReadablePart: "nsec", data: Array(repeating: 1, count: 31))

        #expect(PrivateKeyValidator.validate(key).status == .malformed(.nostr, .wrongLength(expected: 32, actual: 31)))
    }

    @Test
    func validate_npubIsAPublicKey() {
        #expect(PrivateKeyValidator.validate(Fixtures.nip19PublicKey).status == .publicKey(.nostr))
    }

    // MARK: - OpenSSH

    @Test(arguments: [
        ("ssh-ed25519", PrivateKeyAlgorithm.ed25519),
        ("ssh-rsa", .rsa),
        ("ecdsa-sha2-nistp256", .ecdsa(.p256)),
        ("ecdsa-sha2-nistp521", .ecdsa(.p521)),
        ("sk-ssh-ed25519@openssh.com", .ed25519SecurityKey),
    ])
    func validate_openSSHKeyNamesItsType(keyType: String, algorithm: PrivateKeyAlgorithm) {
        let key = Fixtures.openSSHKey(keyType: keyType)

        let result = PrivateKeyValidator.validate(key)

        #expect(result.status == .valid(.openSSH(algorithm: algorithm, isPassphraseProtected: false)))
        #expect(result.canonicalKey == nil, "An armored key is kept as entered")
    }

    @Test
    func validate_openSSHKeyOfATypeVaultDoesntNameIsStillValid() {
        let key = Fixtures.openSSHKey(keyType: "ssh-future-type")

        #expect(
            PrivateKeyValidator.validate(key).status == .valid(.openSSH(algorithm: nil, isPassphraseProtected: false)),
        )
    }

    @Test
    func validate_openSSHKeyWithAPassphrase() {
        let key = Fixtures.openSSHKey(cipher: "aes256-ctr")

        #expect(
            PrivateKeyValidator.validate(key).status
                == .valid(.openSSH(algorithm: .ed25519, isPassphraseProtected: true)),
        )
    }

    @Test
    func validate_openSSHKeyWhoseChecksDifferIsInconsistent() {
        let key = Fixtures.openSSHKey(checks: (1, 2))

        #expect(PrivateKeyValidator.validate(key).status == .malformed(.openSSH, .inconsistent))
    }

    @Test
    func validate_openSSHKeyWithWindowsLineEndingsOrTextAroundIt() {
        let key = Fixtures.openSSHKey()

        for text in [key.replacing("\n", with: "\r\n"), "My server's key:\n\n" + key + "\nThat's all."] {
            #expect(
                PrivateKeyValidator.validate(text).status
                    == .valid(.openSSH(algorithm: .ed25519, isPassphraseProtected: false)),
            )
        }
    }

    @Test
    func validate_openSSHKeyWithoutItsEndLineIsUnreadable() throws {
        let key = Fixtures.openSSHKey()
        let endLine = try #require(key.split(separator: "\n").last)

        let result = PrivateKeyValidator.validate(key.replacing(endLine, with: ""))

        #expect(result.status == .malformed(.openSSH, .unreadable))
    }

    @Test
    func validate_openSSHKeyWithACharacterThatIsntBase64IsUnreadable() {
        var lines = Fixtures.openSSHKey().split(separator: "\n").map(String.init)
        lines[1] = "!" + lines[1].dropFirst()

        #expect(PrivateKeyValidator.validate(lines.joined(separator: "\n")).status == .malformed(.openSSH, .unreadable))
    }

    @Test
    func validate_openSSHArmorAroundSomethingElseIsUnreadable() {
        let key = Fixtures.armored("OPENSSH PRIVATE KEY", data: Array("not a key".utf8))

        #expect(PrivateKeyValidator.validate(key).status == .malformed(.openSSH, .unreadable))
    }

    @Test(arguments: [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleOnlyExampleOnlyExampleOnly",
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ user@example.com",
        "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTY comment",
    ])
    func validate_openSSHPublicKeyLineIsAPublicKey(line: String) {
        #expect(PrivateKeyValidator.validate(line).status == .publicKey(.openSSH))
    }

    // MARK: - OpenPGP

    @Test
    func validate_openPGPEd25519Key() {
        #expect(PrivateKeyValidator.validate(Fixtures.openPGPKey()).status == .valid(.openPGP(algorithm: .ed25519)))
    }

    @Test(arguments: [
        (UInt8(1), PrivateKeyAlgorithm.rsa),
        (17, .dsa),
        (27, .ed25519),
        (25, .x25519),
    ])
    func validate_openPGPKeyNamesItsAlgorithm(algorithm: UInt8, expected: PrivateKeyAlgorithm) {
        let packet = Fixtures.openPGPSecretKeyPacket(algorithm: algorithm, curveOID: nil)

        #expect(PrivateKeyValidator.validate(Fixtures.openPGPKey(packet: packet)).status == .valid(.openPGP(
            algorithm: expected,
        )))
    }

    @Test
    func validate_openPGPKeyInTheNewPacketFormat() {
        var packet = Fixtures.openPGPSecretKeyPacket()
        // The same packet, with a new format header: 0xC0 | tag.
        packet[0] = 0xC5

        #expect(
            PrivateKeyValidator.validate(Fixtures.openPGPKey(packet: packet)).status
                == .valid(.openPGP(algorithm: .ed25519)),
        )
    }

    @Test
    func validate_openPGPKeyWithoutAChecksumIsStillValid() {
        let key = Fixtures.openPGPKey(includesChecksum: false)

        #expect(PrivateKeyValidator.validate(key).status == .valid(.openPGP(algorithm: .ed25519)))
    }

    @Test
    func validate_openPGPKeyWithTheWrongChecksum() {
        let key = Fixtures.openPGPKey(checksum: 0x123456)

        #expect(PrivateKeyValidator.validate(key).status == .invalidChecksum(.openPGP))
    }

    @Test
    func validate_openPGPKeyChangedAfterItsChecksumWasMade() {
        let packet = Fixtures.openPGPSecretKeyPacket()
        var changed = packet
        changed[30] ^= 0x01

        let key = Fixtures.openPGPKey(packet: changed, checksum: CRC24.checksum(packet))

        #expect(PrivateKeyValidator.validate(key).status == .invalidChecksum(.openPGP))
    }

    @Test
    func validate_openPGPPublicKeyIsAPublicKey() {
        let publicPacket = Fixtures.openPGPSecretKeyPacket(tag: 6)

        #expect(PrivateKeyValidator.validate(Fixtures.openPGPKey(packet: publicPacket)).status == .publicKey(.openPGP))
        #expect(PrivateKeyValidator.validate(Fixtures.openPGPKey(label: "PGP PUBLIC KEY BLOCK")).status
            == .publicKey(.openPGP))
    }

    @Test
    func validate_openPGPBlockThatIsntAKeyIsUnreadable() {
        // A literal data packet (tag 11).
        let packet = Fixtures.openPGPSecretKeyPacket(tag: 11)

        #expect(PrivateKeyValidator.validate(Fixtures.openPGPKey(packet: packet)).status
            == .malformed(.openPGP, .unreadable))
    }

    // MARK: - PEM

    @Test
    func validate_pkcs8Ed25519() {
        let key = Fixtures.armored("PRIVATE KEY", data: Fixtures.pkcs8Ed25519)

        #expect(PrivateKeyValidator.validate(key).status == .valid(.pem(
            .pkcs8,
            algorithm: .ed25519,
            isEncrypted: false,
        )))
    }

    @Test
    func validate_pkcs8Secp256k1() {
        let key = Fixtures.armored("PRIVATE KEY", data: Fixtures.pkcs8Secp256k1)

        #expect(
            PrivateKeyValidator.validate(key).status
                == .valid(.pem(.pkcs8, algorithm: .ec(.secp256k1), isEncrypted: false)),
        )
    }

    @Test
    func validate_sec1Secp256k1() {
        let key = Fixtures.armored("EC PRIVATE KEY", data: Fixtures.sec1Secp256k1)

        #expect(
            PrivateKeyValidator.validate(key).status
                == .valid(.pem(.sec1, algorithm: .ec(.secp256k1), isEncrypted: false)),
        )
    }

    @Test
    func validate_pkcs1RSA() {
        let key = Fixtures.armored("RSA PRIVATE KEY", data: Fixtures.pkcs1RSA)

        #expect(PrivateKeyValidator.validate(key).status == .valid(.pem(.pkcs1, algorithm: .rsa, isEncrypted: false)))
    }

    @Test
    func validate_encryptedPKCS8() {
        let key = Fixtures.armored("ENCRYPTED PRIVATE KEY", data: Fixtures.encryptedPKCS8)

        #expect(PrivateKeyValidator.validate(key).status == .valid(.pem(.pkcs8, algorithm: nil, isEncrypted: true)))
    }

    /// A legacy encrypted key says so in its headers, and what follows is encrypted, so isn't read.
    @Test
    func validate_legacyEncryptedPEM() {
        let key = Fixtures.armored(
            "RSA PRIVATE KEY",
            data: Array(repeating: 0x99, count: 48),
            headers: ["Proc-Type: 4,ENCRYPTED", "DEK-Info: AES-256-CBC,EF7B935035F4FE083FA20566751C833A"],
        )

        #expect(PrivateKeyValidator.validate(key).status == .valid(.pem(.pkcs1, algorithm: .rsa, isEncrypted: true)))
    }

    @Test(arguments: ["PRIVATE KEY", "EC PRIVATE KEY", "RSA PRIVATE KEY", "ENCRYPTED PRIVATE KEY"])
    func validate_pemThatIsntDERIsUnreadable(label: String) {
        let key = Fixtures.armored(label, data: Array("not DER at all".utf8))

        #expect(PrivateKeyValidator.validate(key).status == .malformed(.pem, .unreadable))
    }

    @Test(arguments: ["PUBLIC KEY", "RSA PUBLIC KEY"])
    func validate_pemPublicKeyIsAPublicKey(label: String) {
        let key = Fixtures.armored(label, data: Fixtures.pkcs1RSA)

        #expect(PrivateKeyValidator.validate(key).status == .publicKey(.pem))
    }

    // MARK: - Large input

    /// A long paste is checked without trouble, and isn't read as Base58, which takes time in its length squared.
    @Test
    func validate_veryLongTextIsUnrecognized() {
        let text = String(repeating: "5HueCGU8rMjxEXxiPuD5BDku4MkFqeZyd4dZ1jvhTVqvbTLvyTJ", count: 2000)

        #expect(PrivateKeyValidator.validate(text).status == .unrecognized)
    }
}

// MARK: - Helpers

extension PrivateKeyValidatorTests {
    private func hexBytes(_ hex: String) throws -> [UInt8] {
        var bytes = [UInt8]()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            try bytes.append(#require(UInt8(hex[index ..< next], radix: 16)))
            index = next
        }
        return bytes
    }
}

extension ExtendedKeyVersion: CustomTestStringConvertible {
    public var testDescription: String {
        prefix
    }
}
