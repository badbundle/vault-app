import CryptoKit
import Foundation
import FoundationExtensions
@testable import VaultFeed

/// Keeps the device key in memory, and fails when the test says.
final class InMemoryDeviceKeyStore: VaultDeviceKeyStoring {
    struct Failure: Error {}

    private struct State {
        var key: SymmetricKey?
        var failsToMake = false
        var failsToRemove = false
    }

    private let state: SharedMutex<State>

    init(key: SymmetricKey? = nil) {
        state = SharedMutex(State(key: key))
    }

    /// The key as it's stored now.
    var key: SymmetricKey? {
        state.get { $0.key }
    }

    func failToMake() {
        state.modify { $0.failsToMake = true }
    }

    func failToRemove() {
        state.modify { $0.failsToRemove = true }
    }

    func deviceKey() throws -> SymmetricKey? {
        state.get { $0.key }
    }

    func makeNewDeviceKey() throws -> SymmetricKey {
        try state.modify { state in
            guard !state.failsToMake else { throw Failure() }
            let key = SymmetricKey(size: .bits256)
            state.key = key
            return key
        }
    }

    func removeDeviceKey() throws {
        try state.modify { state in
            guard !state.failsToRemove else { throw Failure() }
            state.key = nil
        }
    }
}
