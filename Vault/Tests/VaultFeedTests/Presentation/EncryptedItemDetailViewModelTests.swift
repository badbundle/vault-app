import Foundation
import TestHelpers
import Testing
@testable import VaultFeed

@MainActor
final class EncryptedItemDetailViewModelTests {
    @Test
    func canStartDecryption_isInitiallyFalse() {
        let sut = makeSUT(item: anyEncryptedItem())

        #expect(sut.canStartDecryption == false)
    }

    @Test
    func canStartDecryption_trueWhenPasswordIsEntered() {
        let sut = makeSUT(item: anyEncryptedItem())
        sut.enteredEncryptionPassword = "hello"

        #expect(sut.canStartDecryption == true)
    }

    @Test
    func state_isInitiallyBase() {
        let sut = makeSUT(item: anyEncryptedItem())

        #expect(sut.state == .base)
    }

    @Test
    func startDecryption_setsStateToDecrypting() async {
        let keyDeriverFactory = VaultKeyDeriverFactoryMock()
        let handlerCalled = Pending.signal()
        let keyDeriver = SuspendingKeyDeriver<32> { _, _ in
            Task { await handlerCalled.fulfill() }
            return .random()
        }
        keyDeriverFactory.lookupVaultKeyDeriverHandler = { _ in .init(deriver: keyDeriver, signature: .testing) }
        let sut = makeSUT(item: anyEncryptedItem(), keyDeriverFactory: keyDeriverFactory)
        sut.enteredEncryptionPassword = "hello"

        Task.detached {
            await sut.startDecryption()
        }

        try? await handlerCalled.wait()

        #expect(sut.state == .decrypting)

        keyDeriver.signalDerivationComplete()
    }

    @Test
    func startDecryption_secureNote() async throws {
        let note = SecureNote(title: "Hello", contents: "World", format: .plain)
        let derivedKey = try VaultKeyDeriver.testing.createEncryptionKey(password: "hello")
        let encryptor = VaultItemEncryptor(key: derivedKey)
        let encryptedItem = try encryptor.encrypt(item: note)

        let keyDeriverFactory = VaultKeyDeriverFactoryMock()
        keyDeriverFactory.lookupVaultKeyDeriverHandler = { _ in .testing }
        let sut = makeSUT(item: encryptedItem, keyDeriverFactory: keyDeriverFactory)
        sut.enteredEncryptionPassword = "hello"

        await sut.startDecryption()

        switch sut.state {
        case let .decrypted(.secureNote(decryptedNote), key):
            #expect(decryptedNote == note)
            #expect(key == derivedKey)
        default:
            Issue.record("Unexpected state \(sut.state)")
        }
    }

    @Test
    func startDecryption_recoveryPhrase() async throws {
        let phrase = anyRecoveryPhrase(title: "Wallet", passphrase: "extra")
        let derivedKey = try VaultKeyDeriver.testing.createEncryptionKey(password: "hello")
        let encryptor = VaultItemEncryptor(key: derivedKey)
        let encryptedItem = try encryptor.encrypt(item: phrase)

        let keyDeriverFactory = VaultKeyDeriverFactoryMock()
        keyDeriverFactory.lookupVaultKeyDeriverHandler = { _ in .testing }
        let sut = makeSUT(item: encryptedItem, keyDeriverFactory: keyDeriverFactory)
        sut.enteredEncryptionPassword = "hello"

        await sut.startDecryption()

        switch sut.state {
        case let .decrypted(.recoveryPhrase(decryptedPhrase), key):
            #expect(decryptedPhrase == phrase)
            #expect(key == derivedKey)
        default:
            Issue.record("Unexpected state \(sut.state)")
        }
    }

    @Test
    func startDecryption_unknownItem() async throws {
        let encryptable = VaultItemEncryptableMock(
            itemIdentifier: "this is invalid",
        )
        let derivedKey = try VaultKeyDeriver.testing.createEncryptionKey(password: "hello")
        let encryptor = VaultItemEncryptor(key: derivedKey)
        let encryptedItem = try encryptor.encrypt(item: encryptable)

        let keyDeriverFactory = VaultKeyDeriverFactoryMock()
        keyDeriverFactory.lookupVaultKeyDeriverHandler = { _ in .testing }
        let sut = makeSUT(item: encryptedItem, keyDeriverFactory: keyDeriverFactory)
        sut.enteredEncryptionPassword = "hello"

        await sut.startDecryption()

        switch sut.state {
        case let .decryptionError(error):
            #expect(error.userTitle == "Error")
            #expect(
                error.userDescription
                    ==
                    "Your password was correct, but the item that was encrypted is not known to Vault. We can't display it.",
            )
        default:
            Issue.record("Unexpected state \(sut.state)")
        }
    }

    @Test
    func startDecryption_invalidPassword() async throws {
        let encryptable = VaultItemEncryptableMock(
            itemIdentifier: "any",
        )
        let derivedKey = try VaultKeyDeriver.testing.createEncryptionKey(password: "hello")
        let encryptor = VaultItemEncryptor(key: derivedKey)
        let encryptedItem = try encryptor.encrypt(item: encryptable)

        let keyDeriverFactory = VaultKeyDeriverFactoryMock()
        keyDeriverFactory.lookupVaultKeyDeriverHandler = { _ in .testing }
        let sut = makeSUT(item: encryptedItem, keyDeriverFactory: keyDeriverFactory)
        sut.enteredEncryptionPassword = "incorrect password"

        await sut.startDecryption()

        switch sut.state {
        case let .decryptionError(error):
            #expect(error.userTitle == "Incorrect Password")
            #expect(error.userDescription == "Your password was not recognized, please try again.")
        default:
            Issue.record("Unexpected state \(sut.state)")
        }
    }
}

// MARK: - Helpers

extension EncryptedItemDetailViewModelTests {
    private func makeSUT(
        item: EncryptedItem,
        metadata: VaultItem.Metadata = anyVaultItemMetadata(),
        keyDeriverFactory: VaultKeyDeriverFactoryMock = VaultKeyDeriverFactoryMock(),
    ) -> EncryptedItemDetailViewModel {
        EncryptedItemDetailViewModel(item: item, metadata: metadata, keyDeriverFactory: keyDeriverFactory)
    }
}
