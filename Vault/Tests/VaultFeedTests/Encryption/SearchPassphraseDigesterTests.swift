import CryptoKit
import Foundation
import FoundationExtensions
import Testing
@testable import VaultFeed

struct SearchPassphraseDigesterTests {
    @Test
    func makeDigest_generatesSixteenByteSalt() {
        let sut = makeSUT()

        let digest = sut.makeDigest(phrase: "hello")

        #expect(digest.salt.count == SearchPassphraseDigester.saltLength)
    }

    @Test
    func makeDigest_generatesThirtyTwoByteDigest() {
        let sut = makeSUT()

        let digest = sut.makeDigest(phrase: "hello")

        #expect(digest.digest.count == 32)
    }

    @Test
    func makeDigest_usesDistinctSaltsAcrossCalls() {
        let sut = makeSUT()

        let first = sut.makeDigest(phrase: "hello")
        let second = sut.makeDigest(phrase: "hello")

        #expect(first.salt != second.salt)
        #expect(first.digest != second.digest)
    }

    @Test
    func matches_returnsTrueForCorrectPhrase() {
        let sut = makeSUT()
        let digest = sut.makeDigest(phrase: "correct horse battery staple")

        #expect(sut.matches(query: "correct horse battery staple", salt: digest.salt, digest: digest.digest))
    }

    @Test
    func matches_returnsFalseForWrongPhrase() {
        let sut = makeSUT()
        let digest = sut.makeDigest(phrase: "correct horse battery staple")

        #expect(sut.matches(query: "wrong", salt: digest.salt, digest: digest.digest) == false)
    }

    @Test
    func matches_returnsFalseForWrongSalt() {
        let sut = makeSUT()
        let digest = sut.makeDigest(phrase: "hello")
        let otherSalt = Data(repeating: 0xFF, count: SearchPassphraseDigester.saltLength)

        #expect(sut.matches(query: "hello", salt: otherSalt, digest: digest.digest) == false)
    }

    @Test
    func matches_returnsFalseForDifferentKey() throws {
        let phrase = "secret"
        let keyA = try KeyData<32>(data: Data(repeating: 0x01, count: 32))
        let keyB = try KeyData<32>(data: Data(repeating: 0x02, count: 32))
        let digesterA = SearchPassphraseDigester(key: keyA)
        let digesterB = SearchPassphraseDigester(key: keyB)
        let digest = digesterA.makeDigest(phrase: phrase)

        #expect(digesterB.matches(query: phrase, salt: digest.salt, digest: digest.digest) == false)
        #expect(digesterA.matches(query: phrase, salt: digest.salt, digest: digest.digest))
    }

    @Test
    func matches_isCaseInsensitive() {
        let sut = makeSUT()
        let digest = sut.makeDigest(phrase: "Hello")

        #expect(sut.matches(query: "hello", salt: digest.salt, digest: digest.digest))
        #expect(sut.matches(query: "HELLO", salt: digest.salt, digest: digest.digest))
        #expect(sut.matches(query: "hElLo", salt: digest.salt, digest: digest.digest))
    }

    @Test
    func matches_handlesUnicodeNormalizationVariants() {
        let sut = makeSUT()
        // "café" composed (NFC: U+00E9) vs decomposed (NFD: e + U+0301).
        // The digester normalises both sides, so these must match.
        let composed = "caf\u{00E9}"
        let decomposed = "cafe\u{0301}"
        let digest = sut.makeDigest(phrase: composed)

        #expect(sut.matches(query: decomposed, salt: digest.salt, digest: digest.digest))
        #expect(sut.matches(query: decomposed.uppercased(), salt: digest.salt, digest: digest.digest))
    }

    @Test
    func matches_returnsFalseForEmptyQuery() {
        let sut = makeSUT()
        let digest = sut.makeDigest(phrase: "hello")

        #expect(sut.matches(query: "", salt: digest.salt, digest: digest.digest) == false)
    }
}

extension SearchPassphraseDigesterTests {
    /// A restored backup's items keep the digests they were made with elsewhere, which match through the keys the
    /// backup brought.
    @Test
    func matches_digestMadeWithAKeyFromABackup() {
        let backupKey = KeyData<32>.repeating(byte: 0xB0)
        let digest = SearchPassphraseDigester(key: backupKey).makeDigest(phrase: "find me")
        let sut = SearchPassphraseDigester(
            key: .repeating(byte: 0xD0),
            keysFromBackups: [.repeating(byte: 0xC0), backupKey],
        )

        #expect(sut.matches(query: "find me", salt: digest.salt, digest: digest.digest))
        #expect(sut.matches(query: "not it", salt: digest.salt, digest: digest.digest) == false)
    }

    @Test
    func matches_digestMadeWithAKeyNotOnTheKeyring_isFalse() {
        let digest = SearchPassphraseDigester(key: .repeating(byte: 0xE0)).makeDigest(phrase: "find me")
        let sut = SearchPassphraseDigester(key: .repeating(byte: 0xD0), keysFromBackups: [.repeating(byte: 0xC0)])

        #expect(sut.matches(query: "find me", salt: digest.salt, digest: digest.digest) == false)
    }

    /// A phrase set on this device is always digested with its own key, never one a backup brought.
    @Test
    func makeDigest_usesTheDevicesOwnKey() {
        let ownKey = KeyData<32>.repeating(byte: 0xD0)
        let backupKey = KeyData<32>.repeating(byte: 0xB0)
        let sut = SearchPassphraseDigester(key: ownKey, keysFromBackups: [backupKey])

        let digest = sut.makeDigest(phrase: "find me")

        #expect(SearchPassphraseDigester(key: ownKey).matches(
            query: "find me",
            salt: digest.salt,
            digest: digest.digest,
        ))
        #expect(SearchPassphraseDigester(key: backupKey).matches(
            query: "find me",
            salt: digest.salt,
            digest: digest.digest,
        ) == false)
    }
}

extension SearchPassphraseDigesterTests {
    private func makeSUT() -> SearchPassphraseDigester {
        SearchPassphraseDigester(key: testKey())
    }

    private func testKey() -> KeyData<32> {
        (try? KeyData<32>(data: Data(repeating: 0xBB, count: 32))) ?? .zero()
    }
}
