import Foundation
import FoundationExtensions
import Testing
@testable import VaultFeed

struct VaultPhraseKeyringsTests {
    @Test
    func add_skipsTheOwnKeyAndKeysAlreadyThere_andKeepsTheOrderTheyCame() {
        let own = KeyData<32>.repeating(byte: 0x01)
        var sut = VaultPhraseKeyrings.Keyring(ownKey: own)

        let added = sut.add([.repeating(byte: 0x03), own, .repeating(byte: 0x02), .repeating(byte: 0x03)])
        let addedAgain = sut.add([.repeating(byte: 0x02), own])

        #expect(added)
        #expect(!addedAgain)
        #expect(sut.keysFromBackups == [.repeating(byte: 0x03), .repeating(byte: 0x02)])
        #expect(sut.allKeys == [own, .repeating(byte: 0x03), .repeating(byte: 0x02)])
    }

    @Test
    func init_neverHoldsTheOwnKeyOrOneTwiceAmongTheOthers() {
        let own = KeyData<32>.repeating(byte: 0x01)

        let sut = VaultPhraseKeyrings.Keyring(
            ownKey: own,
            keysFromBackups: [own, .repeating(byte: 0x02), .repeating(byte: 0x02)],
        )

        #expect(sut.keysFromBackups == [.repeating(byte: 0x02)])
    }

    @Test
    func random_givesEachKindAKeyOfItsOwn() {
        let sut = VaultPhraseKeyrings.random()
        let other = VaultPhraseKeyrings.random()

        #expect(sut.killphrase.ownKey != sut.searchPassphrase.ownKey)
        #expect(sut.killphrase.ownKey != other.killphrase.ownKey)
        #expect(sut.killphrase.keysFromBackups.isEmpty)
        #expect(sut.searchPassphrase.keysFromBackups.isEmpty)
    }

    /// A vault that takes a copy of keys it shares never makes a digest with one of them: it gets a key of its own,
    /// and they're only matched against.
    @Test
    func takingCopies_givesANewKeyOfItsOwnAndEveryKeyToMatchAgainst() {
        let shared = [KeyData<32>.repeating(byte: 0x0A), .repeating(byte: 0x0B)]

        let sut = VaultPhraseKeyrings.takingCopies(killphraseKeys: shared, searchPassphraseKeys: [])
        let other = VaultPhraseKeyrings.takingCopies(killphraseKeys: shared, searchPassphraseKeys: [])

        #expect(!shared.contains(sut.killphrase.ownKey))
        #expect(sut.killphrase.keysFromBackups == shared)
        #expect(sut.searchPassphrase.keysFromBackups.isEmpty)
        #expect(sut.killphrase.ownKey != other.killphrase.ownKey)
    }

    /// Keys a payload holds already stay its own; the others are added to match against.
    @Test
    func adding_keepsTheOwnKeysAndAddsEveryOtherKey() {
        let sut = VaultPhraseKeyrings.random()
        var other = VaultPhraseKeyrings.random()
        other.searchPassphrase.add([.repeating(byte: 0x0C)])

        let added = sut.adding(other)

        #expect(added.killphrase.ownKey == sut.killphrase.ownKey)
        #expect(added.killphrase.keysFromBackups == [other.killphrase.ownKey])
        #expect(added.searchPassphrase.keysFromBackups == [other.searchPassphrase.ownKey, .repeating(byte: 0x0C)])
    }

    @Test
    func codable_roundTrips() throws {
        var sut = VaultPhraseKeyrings.random()
        sut.killphrase.add([.repeating(byte: 0x0D)])

        let decoded = try JSONDecoder().decode(VaultPhraseKeyrings.self, from: JSONEncoder().encode(sut))

        #expect(decoded == sut)
    }

    /// Like every key, a keyring's never shows its bytes in a description (G82).
    @Test
    func description_leavesOutTheKeys() {
        let sut = VaultPhraseKeyrings(
            killphrase: .init(ownKey: .repeating(byte: 0xAB), keysFromBackups: [.repeating(byte: 0xCD)]),
            searchPassphrase: .init(ownKey: .repeating(byte: 0xEF)),
        )

        let description = String(describing: sut) + String(reflecting: sut)

        #expect(!description.lowercased().contains("abab"))
        #expect(!description.lowercased().contains("cdcd"))
        #expect(!description.contains("171"))
    }
}
