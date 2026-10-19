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

    /// Whatever its stored lock state, as a recovery phrase (G105).
    @Test
    func requiresDeviceAuthentication_privateKey_always() {
        let privateKey = PrivateKey(title: "Wallet", key: "KwdMAjGmerYanjeui5SHS7JkmpZvVipYvB2LJGU1ZxJwYvP98617")

        #expect(VaultMacEncryptedItemDetailView.requiresDeviceAuthentication(.privateKey(privateKey)))
        #expect(VaultMacEncryptedItemDetailView.authenticationReason(.privateKey(privateKey)) == "Show the private key")
    }

    /// A note's page has already asked for them if its item is locked.
    @Test
    func requiresDeviceAuthentication_note_never() {
        let note = SecureNote(title: "Note", contents: "Contents", format: .plain)

        #expect(!VaultMacEncryptedItemDetailView.requiresDeviceAuthentication(.secureNote(note)))
    }
}
