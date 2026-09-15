import CryptoKit
import Foundation
import FoundationExtensions
import Testing
@testable import VaultFeed

struct KillphraseDigesterTests {
    @Test
    func makeDigest_generatesSixteenByteSalt() {
        let sut = makeSUT()

        let digest = sut.makeDigest(phrase: "hello")

        #expect(digest.salt.count == KillphraseDigester.saltLength)
    }

    @Test
    func makeDigest_generatesThirtyTwoByteDigest() {
        let sut = makeSUT()

        let digest = sut.makeDigest(phrase: "hello")

        // HMAC-SHA256 output is always 32 bytes.
        #expect(digest.digest.count == 32)
    }

    @Test
    func makeDigest_usesDistinctSaltsAcrossCalls() {
        let sut = makeSUT()

        let first = sut.makeDigest(phrase: "hello")
        let second = sut.makeDigest(phrase: "hello")

        // Same phrase + same key but two independent random salts must
        // produce two distinct outputs, otherwise the per-item salt is
        // not actually being randomised.
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
        let otherSalt = Data(repeating: 0xFF, count: KillphraseDigester.saltLength)

        // Same phrase + wrong salt should not verify, even with the same
        // key, otherwise per-item salt is decorative.
        #expect(sut.matches(query: "hello", salt: otherSalt, digest: digest.digest) == false)
    }

    @Test
    func matches_returnsFalseForDifferentKey() throws {
        let phrase = "secret"
        let keyA = try KeyData<32>(data: Data(repeating: 0x01, count: 32))
        let keyB = try KeyData<32>(data: Data(repeating: 0x02, count: 32))
        let digesterA = KillphraseDigester(key: keyA)
        let digesterB = KillphraseDigester(key: keyB)
        let digest = digesterA.makeDigest(phrase: phrase)

        #expect(digesterB.matches(query: phrase, salt: digest.salt, digest: digest.digest) == false)
        // sanity: same key still matches
        #expect(digesterA.matches(query: phrase, salt: digest.salt, digest: digest.digest))
    }

    @Test
    func matches_isCaseSensitive() {
        let sut = makeSUT()
        let digest = sut.makeDigest(phrase: "Hello")

        #expect(sut.matches(query: "hello", salt: digest.salt, digest: digest.digest) == false)
    }

    @Test
    func matches_handlesEmptyQuery() {
        let sut = makeSUT()
        let digest = sut.makeDigest(phrase: "hello")

        #expect(sut.matches(query: "", salt: digest.salt, digest: digest.digest) == false)
    }

    @Test
    func matches_trimsWhitespaceFromQuery() {
        let sut = makeSUT()
        let digest = sut.makeDigest(phrase: "phrase")

        // The search bar delivers the query untrimmed; a trailing space
        // from the keyboard must not stop the killphrase firing.
        #expect(sut.matches(query: "phrase ", salt: digest.salt, digest: digest.digest))
        #expect(sut.matches(query: " phrase\n", salt: digest.salt, digest: digest.digest))
    }

    @Test
    func makeDigest_trimsWhitespaceFromPhrase() {
        let sut = makeSUT()
        let digest = sut.makeDigest(phrase: " phrase ")

        #expect(sut.matches(query: "phrase", salt: digest.salt, digest: digest.digest))
    }

    @Test
    func matches_doesNotTrimInteriorWhitespace() {
        let sut = makeSUT()
        let digest = sut.makeDigest(phrase: "two words")

        #expect(sut.matches(query: "twowords", salt: digest.salt, digest: digest.digest) == false)
        #expect(sut.matches(query: "two words", salt: digest.salt, digest: digest.digest))
    }
}

extension KillphraseDigesterTests {
    private func makeSUT() -> KillphraseDigester {
        KillphraseDigester(key: testKey())
    }

    private func testKey() -> KeyData<32> {
        // The KeyData length is fixed at 32 bytes, and the seed below is
        // also 32 bytes, so this initialiser cannot throw. Using a
        // local helper avoids force-try in every test setup.
        (try? KeyData<32>(data: Data(repeating: 0xAA, count: 32))) ?? .zero()
    }
}
