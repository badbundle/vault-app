import Foundation
import Testing
import VaultFeed
@testable import VaultMac

struct VaultMacEncryptedItemDetailViewTests {
    @Test
    func requiresDeviceAuthentication_recoveryPhrase_always() {
        let phrase = RecoveryPhrase(
            title: "Wallet",
            words: ["abandon", "ability", "able"],
            standard: .bip39,
            passphrase: "",
            contents: "",
        )

        #expect(VaultMacEncryptedItemDetailView.requiresDeviceAuthentication(.recoveryPhrase(phrase)))
    }

    /// A note's page has already asked for them if its item is locked.
    @Test
    func requiresDeviceAuthentication_note_never() {
        let note = SecureNote(title: "Note", contents: "Contents", format: .plain)

        #expect(!VaultMacEncryptedItemDetailView.requiresDeviceAuthentication(.secureNote(note)))
    }
}
