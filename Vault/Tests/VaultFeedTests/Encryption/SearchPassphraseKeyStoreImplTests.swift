import Foundation
import FoundationExtensions
import Testing
import VaultCore
@testable import VaultFeed

struct SearchPassphraseKeyStoreImplTests {
    @Test
    func loadOrCreate_returnsStoredKeyWhenPresent() async throws {
        let existing = Data(repeating: 0x42, count: 32)
        let storage = SecureStorageMock()
        storage.retrieveSilentHandler = { _ in existing }
        let sut = SearchPassphraseKeyStoreImpl(secureStorage: storage)

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
        let sut = SearchPassphraseKeyStoreImpl(secureStorage: storage)

        let key = try await sut.loadOrCreate()

        #expect(storage.storeSilentCallCount == 1)
        let stored = await recorder.stored
        #expect(stored?.data == key.data)
        #expect(key.data.count == 32)
    }

    @Test
    func loadOrCreate_usesSearchPassphraseKeyKeychainIdentifier() async throws {
        let recorder = StoreRecorder()
        let storage = SecureStorageMock()
        storage.retrieveSilentHandler = { _ in nil }
        storage.storeSilentHandler = { data, key in
            await recorder.record(data: data, key: key)
        }
        let sut = SearchPassphraseKeyStoreImpl(secureStorage: storage)

        _ = try await sut.loadOrCreate()

        let stored = await recorder.stored
        #expect(stored?.key == VaultIdentifiers.SecureStorageKey.searchPassphraseKey.rawValue)
    }

    @Test
    func loadOrCreate_usesSilentRetrievalPathNotUserPresence() async throws {
        // Passphrase matching must work without prompting biometric so
        // the keystore must talk to the silent (no-userPresence) channel.
        let storage = SecureStorageMock()
        storage.retrieveSilentHandler = { _ in Data(repeating: 0x01, count: 32) }
        let sut = SearchPassphraseKeyStoreImpl(secureStorage: storage)

        _ = try await sut.loadOrCreate()

        #expect(storage.retrieveSilentCallCount == 1)
        #expect(storage.retrieveCallCount == 0)
    }

    @Test
    func loadOrCreate_freshGenerationProducesNonZeroKey() async throws {
        let storage = SecureStorageMock()
        storage.retrieveSilentHandler = { _ in nil }
        storage.storeSilentHandler = { _, _ in }
        let sut = SearchPassphraseKeyStoreImpl(secureStorage: storage)

        let key = try await sut.loadOrCreate()

        #expect(key.data != Data(repeating: 0, count: 32))
    }
}

extension SearchPassphraseKeyStoreImplTests {
    fileprivate actor StoreRecorder {
        private(set) var stored: (data: Data, key: String)?
        func record(data: Data, key: String) {
            stored = (data, key)
        }
    }
}
