import Foundation
import Testing
import VaultCore
@testable import VaultFeed

/// The demo vault's recovery phrases and private keys, which the App Store screenshots show, are what they say they
/// are: each one checks against its own word list, checksum and format, as one someone stored would.
struct DemoVaultTests {
    @Test(arguments: DemoVault.recoveryPhrases)
    func recoveryPhrase_isValid(_ phrase: RecoveryPhrase) {
        let validation = RecoveryPhraseValidator.validate(words: phrase.words, standard: phrase.standard)

        #expect(validation.isValid, "\(phrase.title) is \(validation.status)")
    }

    @Test
    func recoveryPhrases_areEachOfTheirStandards() {
        let phrases = DemoVault.recoveryPhrases

        #expect(phrases.map(\.standard) == [.bip39, .bip39, .monero, .slip39, .bip39])
        #expect(phrases.map(\.words.count) == [24, 12, 25, 20, 24])
    }

    @Test
    func extendedKey_isABitcoinMasterKey() {
        let validation = PrivateKeyValidator.validate(DemoVault.extendedKey.key)

        guard case let .valid(.extendedKey(version)) = validation.status else {
            Issue.record("Expected an extended key, got \(validation.status)")
            return
        }
        #expect(version.prefix == "xprv")
        #expect(version.network == .bitcoin)
    }

    @Test
    func paperWalletKey_isACompressedMainnetWIFKey() {
        let validation = PrivateKeyValidator.validate(DemoVault.paperWalletKey.key)

        #expect(validation.status == .valid(.wif(network: .mainnet, isCompressed: true)))
    }

    @Test
    func serverSSHKey_isAnUnencryptedOpenSSHEd25519Key() {
        let validation = PrivateKeyValidator.validate(DemoVault.makeServerSSHKey().key)

        #expect(validation.status == .valid(.openSSH(algorithm: .ed25519, isPassphraseProtected: false)))
    }

    @Test
    func serverSSHKey_isMadeAfreshEachTime() {
        #expect(DemoVault.makeServerSSHKey().key != DemoVault.makeServerSSHKey().key)
    }
}
