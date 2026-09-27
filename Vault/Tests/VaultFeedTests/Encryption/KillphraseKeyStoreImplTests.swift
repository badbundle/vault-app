import Foundation
import FoundationExtensions
import Testing
import VaultCore
@testable import VaultFeed

struct KillphraseKeyStoreImplTests {
    @Test
    func loadOrCreate_returnsStoredKeyWhenPresent() async throws {
        let existing = Data(repeating: 0x42, count: 32)
        let storage = SecureStorageMock()
        storage.retrieveSilentHandler = { _ in existing }
        let sut = KillphraseKeyStoreImpl(secureStorage: storage)

        let key = try await sut.loadOrCreate()

        #expect(key.data == existing)
        #expect(storage.storeSilentCallCount == 0)
    }

    @Test
    func loadOrCreate_generatesAndStoresKeyWhenMissing() async throws {
        let recorder = StoreRecorder()
        let storage = SecureStorageMock()
        storage.retrieveSilentHandler = { _ in nil }
        storage.storeSilentHandler = { data, key in
            await recorder.record(data: data, key: key)
        }
        let sut = KillphraseKeyStoreImpl(secureStorage: storage)

        let key = try await sut.loadOrCreate()

        #expect(storage.storeSilentCallCount == 1)
        let stored = await recorder.stored
        #expect(stored?.data == key.data)
        #expect(key.data.count == 32)
    }

    @Test
    func loadOrCreate_usesKillphraseKeyKeychainIdentifier() async throws {
        let recorder = StoreRecorder()
        let storage = SecureStorageMock()
        storage.retrieveSilentHandler = { _ in nil }
        storage.storeSilentHandler = { data, key in
            await recorder.record(data: data, key: key)
        }
        let sut = KillphraseKeyStoreImpl(secureStorage: storage)

        _ = try await sut.loadOrCreate()

        let stored = await recorder.stored
        #expect(stored?.key == VaultIdentifiers.SecureStorageKey.killphraseKey.rawValue)
    }

    @Test
    func loadOrCreate_usesSilentRetrievalPathNotUserPresence() async throws {
        // Killphrase deletion must work without prompting biometric, so
        // the keystore must talk to the silent (no-userPresence) channel.
        let storage = SecureStorageMock()
        storage.retrieveSilentHandler = { _ in Data(repeating: 0x01, count: 32) }
        let sut = KillphraseKeyStoreImpl(secureStorage: storage)

        _ = try await sut.loadOrCreate()

        #expect(storage.retrieveSilentCallCount == 1)
        #expect(storage.retrieveCallCount == 0)
    }

    @Test
    func loadOrCreate_freshGenerationProducesNonZeroKey() async throws {
        let storage = SecureStorageMock()
        storage.retrieveSilentHandler = { _ in nil }
        storage.storeSilentHandler = { _, _ in }
        let sut = KillphraseKeyStoreImpl(secureStorage: storage)

        let key = try await sut.loadOrCreate()

        // Probability that a random 32-byte key is all-zero is 1/2^256.
        // If we observe this, RNG is broken.
        #expect(key.data != Data(repeating: 0, count: 32))
    }
}

extension KillphraseKeyStoreImplTests {
    /// Actor-backed recorder for the `@Sendable` store closure to write
    /// into without tripping captured-var concurrency diagnostics.
    fileprivate actor StoreRecorder {
        private(set) var stored: (data: Data, key: String)?
        func record(data: Data, key: String) {
            stored = (data, key)
        }
    }
}
