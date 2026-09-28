import Combine
import CryptoEngine
import Foundation
import TestHelpers
import Testing
import VaultBackup
import VaultKeygen
@testable import VaultFeed

@MainActor
struct BackupKeyDecryptorViewModelTests {
    @Test @LeakTracked
    func init_setsInitialState() throws {
        let sut = makeSUT()

        #expect(sut.enteredPassword == "")
        #expect(sut.decryptionKeyState == .none)
    }

    @Test @LeakTracked
    func canAttemptDecryption_falseIfPasswordEmpty() throws {
        let sut = makeSUT()
        sut.enteredPassword = ""

        #expect(sut.canAttemptDecryption == false)
    }

    @Test @LeakTracked
    func canAttemptDecryption_trueIfPasswordNotEmpty() throws {
        let sut = makeSUT()
        sut.enteredPassword = "a"

        #expect(sut.canAttemptDecryption)
    }

    @Test @LeakTracked
    func attemptDecryption_validPasswordGeneratesConsistentlyWithSalt() async throws {
        let vaultApplicationPayload = VaultApplicationPayload(userDescription: "my stuff", items: [], tags: [])
        let decoder = EncryptedVaultDecoderMock()
        // returned payload implies successful decryption
        decoder.decryptAndDecodeHandler = { _, _ in vaultApplicationPayload }
        let salt = Data(hex: "1234567890")
        let vault = anyEncryptedVault(salt: salt)
        let subject = PassthroughSubject<VaultApplicationPayload, Never>()
        let sut = makeSUT(
            encryptedVault: vault,
            keyDeriverFactory: .testing,
            encryptedVaultDecoder: decoder,
            decryptedVaultSubject: subject,
        )
        sut.enteredPassword = "hello"

        await confirmation { confirmation in
            let cancel = subject.sink { payload in
                #expect(payload == vaultApplicationPayload)
                confirmation.confirm()
            }

            await sut.attemptDecryption()

            cancel.cancel()
        }

        #expect(sut.decryptionKeyState == .validDecryptionKey)
    }

    @Test @LeakTracked
    func generateKey_emptyPasswordGeneratesError() async throws {
        let decoder = EncryptedVaultDecoderMock()
        decoder.verifyCanDecryptHandler = { _, _ in throw TestError() }
        let sut = makeSUT(encryptedVaultDecoder: decoder)
        sut.enteredPassword = ""

        await sut.attemptDecryption()

        #expect(sut.decryptionKeyState.isError)
    }

    @Test @LeakTracked
    func generateKey_keyDeriverErrorGeneratesError() async throws {
        let sut = makeSUT(keyDeriverFactory: .failing)
        sut.enteredPassword = "hello"

        await sut.attemptDecryption()

        #expect(sut.decryptionKeyState.isError)
    }

    @Test @LeakTracked
    func attemptDecryption_countsEveryFailedAttempt() async throws {
        let decoder = EncryptedVaultDecoderMock()
        decoder.decryptAndDecodeHandler = { _, _ in throw EncryptedVaultDecoderError.decryption }
        let sut = makeSUT(encryptedVaultDecoder: decoder)
        sut.enteredPassword = "wrong"

        await sut.attemptDecryption()
        await sut.attemptDecryption()

        // The same error both times: the count is what changes, so the second wrong password is felt too.
        #expect(sut.decryptionKeyState.isError)
        #expect(sut.failedAttemptCount == 2)
    }

    @Test @LeakTracked
    func attemptDecryption_clearsTheLastErrorWhileDecrypting() async throws {
        let deriver = BlockingKeyDeriver()
        let decoder = EncryptedVaultDecoderMock()
        decoder.decryptAndDecodeHandler = { _, _ in throw EncryptedVaultDecoderError.decryption }
        let sut = makeSUT(keyDeriverFactory: blockingDeriverFactory(deriver), encryptedVaultDecoder: decoder)
        sut.enteredPassword = "wrong"
        deriver.release()
        await sut.attemptDecryption()
        #expect(sut.decryptionKeyState.isError)

        let decryption = Task { await sut.attemptDecryption() }
        while !sut.isDecrypting {
            await Task.yield()
        }

        #expect(sut.decryptionKeyState == .none)

        deriver.release()
        await decryption.value
        #expect(sut.decryptionKeyState.isError)
    }

    @Test @LeakTracked
    func attemptDecryption_cancelledDropsTheKeyWhenItArrives() async throws {
        let deriver = BlockingKeyDeriver()
        let decoder = EncryptedVaultDecoderMock()
        decoder.decryptAndDecodeHandler = { _, _ in anyVaultApplicationPayload() }
        let subject = PassthroughSubject<VaultApplicationPayload, Never>()
        let sut = makeSUT(
            keyDeriverFactory: blockingDeriverFactory(deriver),
            encryptedVaultDecoder: decoder,
            decryptedVaultSubject: subject,
        )
        sut.enteredPassword = "hello"

        await confirmation(expectedCount: 0) { sent in
            let cancellable = subject.sink { _ in sent() }
            let decryption = Task { await sut.attemptDecryption() }
            while !sut.isDecrypting {
                await Task.yield()
            }

            // The deriver can't stop part way, so the key still arrives after the cancel.
            decryption.cancel()
            deriver.release()
            await decryption.value

            cancellable.cancel()
        }

        #expect(decoder.decryptAndDecodeCallCount == 0)
        #expect(sut.decryptionKeyState == .none)
        #expect(sut.failedAttemptCount == 0)
        #expect(sut.isDecrypting == false)
    }
}

// MARK: - Helpers

extension BackupKeyDecryptorViewModelTests {
    @MainActor
    private func makeSUT(
        encryptedVault: EncryptedVault = anyEncryptedVault(),
        keyDeriverFactory: any VaultKeyDeriverFactory = VaultKeyDeriverFactoryTesting(),
        encryptedVaultDecoder: EncryptedVaultDecoderMock = EncryptedVaultDecoderMock(),
        decryptedVaultSubject: PassthroughSubject<VaultApplicationPayload, Never> = .init(),
    ) -> BackupKeyDecryptorViewModel {
        trackForMemoryLeaks(encryptedVaultDecoder)
        return trackForMemoryLeaks(BackupKeyDecryptorViewModel(
            encryptedVault: encryptedVault,
            keyDeriverFactory: keyDeriverFactory,
            encryptedVaultDecoder: encryptedVaultDecoder,
            decryptedVaultSubject: decryptedVaultSubject,
        ))
    }

    private func blockingDeriverFactory(_ deriver: BlockingKeyDeriver) -> VaultKeyDeriverFactoryMock {
        let factory = VaultKeyDeriverFactoryMock()
        factory.lookupVaultKeyDeriverHandler = { _ in
            VaultKeyDeriver(deriver: deriver, signature: .testing)
        }
        return factory
    }

    /// Blocks key derivation until `release()`, so tests can act while the key is being recreated.
    // swiftlint:disable:next no_unchecked_sendable
    private final class BlockingKeyDeriver: KeyDeriver, @unchecked Sendable {
        private let semaphore = DispatchSemaphore(value: 0)

        var uniqueAlgorithmIdentifier: String {
            "blocking"
        }

        func key(password _: Data, salt _: Data) throws -> KeyData<32> {
            semaphore.wait()
            return .zero()
        }

        func release() {
            semaphore.signal()
        }
    }
}
