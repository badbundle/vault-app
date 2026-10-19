import Foundation
import Testing
import VaultCore
@testable import VaultFeed

struct PrivateKeyValidationSummaryTests {
    /// The format, as the item's page and the editor show it.
    @Test(arguments: [
        (PrivateKeyFormat.wif(network: .mainnet, isCompressed: true), "WIF · mainnet · compressed"),
        (.wif(network: .testnet, isCompressed: false), "WIF · testnet · uncompressed"),
        (.hex, "Hex · 32 bytes"),
        (.nostr, "Nostr · nsec"),
        (.openSSH(algorithm: .ed25519, isPassphraseProtected: false), "OpenSSH · Ed25519"),
        (
            .openSSH(algorithm: .ecdsa(.p256), isPassphraseProtected: true),
            "OpenSSH · ECDSA P-256 · passphrase protected",
        ),
        (.openSSH(algorithm: nil, isPassphraseProtected: false), "OpenSSH"),
        (.openPGP(algorithm: .ed25519), "OpenPGP · Ed25519"),
        (.openPGP(algorithm: nil), "OpenPGP"),
        (.pem(.pkcs8, algorithm: .ed25519, isEncrypted: false), "PEM · PKCS #8 · Ed25519"),
        (.pem(.sec1, algorithm: .ec(.secp256k1), isEncrypted: false), "PEM · SEC 1 · EC secp256k1"),
        (.pem(.pkcs1, algorithm: .rsa, isEncrypted: true), "PEM · PKCS #1 · RSA · encrypted"),
        (.pem(.pkcs8, algorithm: nil, isEncrypted: true), "PEM · PKCS #8 · encrypted"),
    ])
    func valid_describesTheFormat(format: PrivateKeyFormat, expected: String) {
        let sut = PrivateKeyValidationSummary(validation: .init(status: .valid(format)))

        #expect(sut.kind == .valid)
        #expect(sut.title == "Valid private key")
        #expect(sut.detail == expected)
    }

    @Test(arguments: [
        ("xprv", "xprv · mainnet"),
        ("zprv", "zprv · mainnet · native SegWit"),
        ("Yprv", "Yprv · mainnet · nested SegWit multisig"),
        ("tprv", "tprv · testnet"),
        ("Ltpv", "Ltpv · Litecoin"),
        ("dgpv", "dgpv · Dogecoin"),
    ])
    func valid_describesTheExtendedKeysVersion(prefix: String, expected: String) throws {
        let version = try #require(ExtendedKeyVersion.privateKeyVersions.first { $0.prefix == prefix })

        let sut = PrivateKeyValidationSummary(validation: .init(status: .valid(.extendedKey(version))))

        #expect(sut.detail == expected)
        #expect(sut.kindTitle == "Extended Key")
    }

    @Test
    func invalidChecksum_saysWhatItLooksLike() {
        let sut = PrivateKeyValidationSummary(validation: .init(status: .invalidChecksum(.nostr)))

        #expect(sut.kind == .warning)
        #expect(sut.title == "Checksum doesn't match")
        #expect(sut.detail.contains("a Nostr key"))
    }

    @Test
    func wrongLength_ofAHexKeyCountsItsDigits() {
        let sut = PrivateKeyValidationSummary(validation: .init(status: .malformed(
            .hex,
            .wrongLength(expected: 64, actual: 63),
        )))

        #expect(sut.kind == .warning)
        #expect(sut.detail == "A raw key is 64 hexadecimal digits, but this has 63. Check it against your backup.")
    }

    @Test
    func wrongLength_ofAnotherKeyCountsItsBytes() {
        let sut = PrivateKeyValidationSummary(validation: .init(status: .malformed(
            .nostr,
            .wrongLength(expected: 32, actual: 31),
        )))

        #expect(sut
            .detail ==
            "This looks like a Nostr key, which holds 32 bytes, but this holds 31. Check it against your backup.")
    }

    @Test(arguments: [
        PrivateKeyProblem.outOfRange, .unknownVersion, .unreadable, .inconsistent,
    ])
    func malformed_isAWarning(problem: PrivateKeyProblem) {
        let sut = PrivateKeyValidationSummary(validation: .init(status: .malformed(.extendedKey, problem)))

        #expect(sut.kind == .warning)
        #expect(sut.detail.contains("an extended private key"))
    }

    @Test
    func publicKey_warnsItsNotThePrivateKey() {
        let sut = PrivateKeyValidationSummary(validation: .init(status: .publicKey(.openSSH)))

        #expect(sut.kind == .warning)
        #expect(sut.title == "This is a public key")
        #expect(sut.kindTitle == "OpenSSH")
    }

    @Test
    func unrecognized_isOtherAndNotChecked() {
        let sut = PrivateKeyValidationSummary(validation: .init(status: .unrecognized))

        #expect(sut.kind == .neutral)
        #expect(sut.title == "Other")
        #expect(sut.kindTitle == "Other")
    }

    @Test
    func empty_isNeutralWithNoKind() {
        let sut = PrivateKeyValidationSummary(validation: .init(status: .empty))

        #expect(sut.kind == .neutral)
        #expect(sut.kindTitle == "")
    }
}

struct PrivateKeyDisplayTests {
    /// Shown with a zero-width space between each character, so it wraps anywhere and is never hyphenated, and is the
    /// same key once they're taken out.
    @Test
    func displayText_isTheKeyWithAZeroWidthSpaceBetweenEachCharacter() {
        let key = "ab\ncd"

        let shown = PrivateKey.displayText(for: key)

        #expect(shown == "a\u{200B}b\u{200B}\n\u{200B}c\u{200B}d")
        #expect(shown.replacing("\u{200B}", with: "") == key)
    }
}
