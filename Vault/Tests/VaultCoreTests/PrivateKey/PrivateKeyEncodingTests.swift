import Foundation
import Testing
@testable import VaultCore

struct PrivateKeyEncodingTests {
    // MARK: - Base58Check

    @Test
    func base58Check_decodesTheWikiExample() {
        // The payload is the version byte 0x80 then the key (https://en.bitcoin.it/wiki/Wallet_import_format).
        guard case let .valid(payload) = Base58Check.decode(PrivateKeyTestFixtures.wifUncompressed) else {
            Issue.record("Didn't decode")
            return
        }
        #expect(payload.first == 0x80)
        #expect(payload.count == 33)
    }

    @Test
    func base58Check_roundTrips() {
        let payloads: [[UInt8]] = [[0], [0, 0, 1], [0xFF, 0xEE], Array(0 ... 77)]

        for payload in payloads {
            #expect(Base58Check.decode(Base58Check.encode(payload)) == .valid(payload: payload))
        }
    }

    @Test(arguments: ["0OIl", "abc!", "", "1"])
    func base58Check_refusesWhatIsntBase58(text: String) {
        #expect(Base58Check.decode(text) == .notBase58)
    }

    @Test
    func base58Check_refusesTooLongText() {
        let text = Base58Check.encode(Array(repeating: 0xAB, count: 100))

        #expect(text.count > Base58Check.maximumLength)
        #expect(Base58Check.decode(text) == .notBase58)
    }

    // MARK: - Bech32

    /// BIP-173's valid checksum test vectors.
    @Test(arguments: [
        "A12UEL5L",
        "a12uel5l",
        "an83characterlonghumanreadablepartthatcontainsthenumber1andtheexcludedcharactersbio1tt5tgs",
        "abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw",
        "split1checkupstagehandshakeupstreamerranterredcaperred2y9e3w",
        "?1ezyfcl",
    ])
    func bech32_acceptsBIP173sValidChecksums(text: String) {
        switch Bech32.decode(text) {
        case .valid, .invalid:
            // Some of the vectors' data doesn't make whole bytes, which is all keys need: only the checksum's tested.
            break
        case .invalidChecksum:
            Issue.record("\(text) has a valid checksum")
        }
    }

    /// BIP-173's invalid test vectors.
    @Test(arguments: [
        "pzry9x0s0muk", // No separator.
        "1pzry9x0s0muk", // Empty human-readable part.
        "x1b4n0q5v", // Invalid data character.
        "li1dgmt3", // Too short checksum.
        "A1G7SGD8", // Checksum calculated with uppercase form of HRP.
        "10a06t8", // Empty HRP.
        "1qzzfhee", // Empty HRP.
        "an84characterslonghumanreadablepartthatcontainsthenumber1andtheexcludedcharactersbio1569pvx", // Too long.
    ])
    func bech32_refusesBIP173sInvalidStrings(text: String) {
        switch Bech32.decode(text) {
        case .valid:
            Issue.record("\(text) isn't valid")
        case .invalidChecksum, .invalid:
            break
        }
    }

    @Test
    func bech32_decodesNIP19sExample() {
        let expected = "67dea2ed018072d675f5415ecfaed7d2597555e202d85b3d65ea4e58d2d92ffa"

        guard case let .valid(hrp, data) = Bech32.decode(PrivateKeyTestFixtures.nip19PrivateKey) else {
            Issue.record("Didn't decode")
            return
        }
        #expect(hrp == "nsec")
        #expect(data.map { String(format: "%02x", $0) }.joined() == expected)
    }

    @Test
    func bech32_roundTrips() {
        let data = Array(0 ..< 32).map(UInt8.init)

        let encoded = Bech32.encode(humanReadablePart: "nsec", data: data)

        #expect(Bech32.decode(encoded) == .valid(humanReadablePart: "nsec", data: data))
    }

    // MARK: - CRC-24

    /// CRC-24/OPENPGP's check value, from the CRC catalogue (https://reveng.sourceforge.io/crc-catalogue/17plus.htm).
    @Test
    func crc24_matchesTheCatalogueCheck() {
        #expect(CRC24.checksum(Array("123456789".utf8)) == 0x21CF02)
    }

    @Test
    func crc24_ofNothingIsItsInitialValue() {
        #expect(CRC24.checksum([UInt8]()) == 0xB704CE)
    }

    // MARK: - secp256k1's range

    @Test
    func secp256k1_rangeIsOneToNMinusOne() {
        var nMinusOne = Secp256k1.order
        nMinusOne[31] -= 1
        let one = Array(repeating: UInt8(0), count: 31) + [1]

        #expect(Secp256k1.isValidPrivateKey(one))
        #expect(Secp256k1.isValidPrivateKey(nMinusOne))
        #expect(!Secp256k1.isValidPrivateKey(Array(repeating: 0, count: 32)))
        #expect(!Secp256k1.isValidPrivateKey(Secp256k1.order))
        #expect(!Secp256k1.isValidPrivateKey(Array(repeating: 0xFF, count: 32)))
        #expect(!Secp256k1.isValidPrivateKey(Array(repeating: 1, count: 31)), "Not 32 bytes")
    }
}
