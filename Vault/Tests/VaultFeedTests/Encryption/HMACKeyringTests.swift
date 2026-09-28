import CryptoKit
import Foundation
import FoundationExtensions
import Testing
import VaultCore
@testable import VaultFeed

/// The keyrings behind `KillphraseKeyStoreImpl` and `SearchPassphraseKeyStoreImpl`: this device's own key, and the
/// keys restored backups brought.
struct HMACKeyringTests {
    @Test
    func loadKeyring_isTheOwnKeyAlone_untilABackupAddsKeys() async throws {
        let sut = KillphraseKeyStoreImpl(secureStorage: InMemorySecureStorage())

        let own = try await sut.loadOrCreate()

        #expect(try await sut.loadKeyring() == [own])
        #expect(try await sut.loadKeysFromBackups() == [])
    }

    @Test
    func addKeysFromBackup_addsKeysAfterTheOwnKey_inTheOrderTheyCame() async throws {
        let sut = KillphraseKeyStoreImpl(secureStorage: InMemorySecureStorage())
        let own = try await sut.loadOrCreate()
        let first = KeyData<32>.repeating(byte: 0x01)
        let second = KeyData<32>.repeating(byte: 0x02)

        try await sut.addKeysFromBackup([first])
        try await sut.addKeysFromBackup([second, first])

        #expect(try await sut.loadKeyring() == [own, first, second])
    }

    @Test
    func addKeysFromBackup_skipsTheOwnKeyAndKeysAlreadyOnTheKeyring() async throws {
        let sut = KillphraseKeyStoreImpl(secureStorage: InMemorySecureStorage())
        let own = try await sut.loadOrCreate()
        let other = KeyData<32>.repeating(byte: 0x07)

        try await sut.addKeysFromBackup([own, other, other])

        #expect(try await sut.loadKeysFromBackups() == [other])
    }

    /// Restoring a backup made on this device, since its last erase, brings no key it doesn't have, so nothing's
    /// written.
    @Test
    func addKeysFromBackup_onlyTheOwnKey_writesNothing() async throws {
        let storage = InMemorySecureStorage()
        let sut = KillphraseKeyStoreImpl(secureStorage: storage)
        let own = try await sut.loadOrCreate()

        try await sut.addKeysFromBackup([own])

        #expect(await !storage.contains(key: VaultIdentifiers.SecureStorageKey.killphraseBackupKeys.rawValue))
    }

    /// A key from a backup never becomes this device's own key, which new digests are made with.
    @Test
    func addKeysFromBackup_beforeThereIsAnOwnKey_makesOneOfItsOwn() async throws {
        let sut = KillphraseKeyStoreImpl(secureStorage: InMemorySecureStorage())
        let fromBackup = KeyData<32>.repeating(byte: 0x03)

        try await sut.addKeysFromBackup([fromBackup])
        let own = try await sut.loadOrCreate()

        #expect(own != fromBackup)
        #expect(try await sut.loadKeyring() == [own, fromBackup])
    }

    @Test
    func keysFromBackups_areKeptInTheKeychain() async throws {
        let storage = InMemorySecureStorage()
        let fromBackup = KeyData<32>.repeating(byte: 0x04)
        try await KillphraseKeyStoreImpl(secureStorage: storage).addKeysFromBackup([fromBackup])

        let reopened = KillphraseKeyStoreImpl(secureStorage: storage)

        #expect(try await reopened.loadKeysFromBackups() == [fromBackup])
    }

    /// Like the device's own key, they're read without a biometric prompt, so matching works as soon as the device is
    /// unlocked.
    @Test
    func keysFromBackups_areReadWithoutUserPresence() async throws {
        let storage = InMemorySecureStorage()
        let sut = KillphraseKeyStoreImpl(secureStorage: storage)

        try await sut.addKeysFromBackup([.repeating(byte: 0x05)])
        _ = try await sut.loadKeyring()

        #expect(await storage.authenticatedRetrieveCount == 0)
    }

    @Test
    func loadKeysFromBackups_ignoresBytesThatAreNotAWholeKey() async throws {
        let storage = InMemorySecureStorage()
        var stored = Data(repeating: 0x0A, count: 32)
        stored.append(Data(repeating: 0x0B, count: 32))
        stored.append(Data(repeating: 0x0C, count: 6))
        await storage.storeSilent(
            data: stored,
            forKey: VaultIdentifiers.SecureStorageKey.killphraseBackupKeys.rawValue,
        )
        let sut = KillphraseKeyStoreImpl(secureStorage: storage)

        let keys = try await sut.loadKeysFromBackups()

        #expect(keys == [.repeating(byte: 0x0A), .repeating(byte: 0x0B)])
    }

    @Test
    func killphraseAndSearchPassphraseKeyrings_areSeparate() async throws {
        let storage = InMemorySecureStorage()
        let killphraseKeys = KillphraseKeyStoreImpl(secureStorage: storage)
        let searchPassphraseKeys = SearchPassphraseKeyStoreImpl(secureStorage: storage)

        try await killphraseKeys.addKeysFromBackup([.repeating(byte: 0x0D)])
        try await searchPassphraseKeys.addKeysFromBackup([.repeating(byte: 0x0E)])

        #expect(try await killphraseKeys.loadKeysFromBackups() == [.repeating(byte: 0x0D)])
        #expect(try await searchPassphraseKeys.loadKeysFromBackups() == [.repeating(byte: 0x0E)])
        #expect(try await killphraseKeys.loadOrCreate() != searchPassphraseKeys.loadOrCreate())
        #expect(await storage.contains(key: VaultIdentifiers.SecureStorageKey.searchPassphraseBackupKeys.rawValue))
    }

    // MARK: - Matching

    @Test(arguments: [0, 1, 2])
    func anyKey_matchesACodeMadeWithAnyKeyOnTheKeyring(index: Int) {
        let keys = [0x01, 0x02, 0x03].map { SymmetricKey(data: Data(repeating: $0, count: 32)) }
        let message = Data("salt and phrase".utf8)
        let code = Data(HMAC<SHA256>.authenticationCode(for: message, using: keys[index]))

        #expect(HMACKeyring.anyKey(of: keys, authenticates: code, message: message))
        #expect(!HMACKeyring.anyKey(of: keys, authenticates: code, message: Data("another phrase".utf8)))
    }

    @Test
    func anyKey_codeMadeWithAKeyNotOnTheKeyring_doesNotMatch() {
        let keys = [0x01, 0x02].map { SymmetricKey(data: Data(repeating: $0, count: 32)) }
        let message = Data("salt and phrase".utf8)
        let other = SymmetricKey(data: Data(repeating: 0x09, count: 32))
        let code = Data(HMAC<SHA256>.authenticationCode(for: message, using: other))

        #expect(!HMACKeyring.anyKey(of: keys, authenticates: code, message: message))
        #expect(!HMACKeyring.anyKey(of: [], authenticates: code, message: message))
    }
}
