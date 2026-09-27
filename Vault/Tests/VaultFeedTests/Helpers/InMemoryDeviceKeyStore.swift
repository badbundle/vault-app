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

/// Wraps a device key store, and makes each of its keychain operations a step of a fault-injecting file system, so a
/// fault can land on them too, counted in with the file steps.
final class FaultInjectingDeviceKeyStore: VaultDeviceKeyStoring {
    private let base: any VaultDeviceKeyStoring
    private let steps: FaultInjectingSlotFileSystem

    init(wrapping base: any VaultDeviceKeyStoring, steps: FaultInjectingSlotFileSystem) {
        self.base = base
        self.steps = steps
    }

    func deviceKey() throws -> SymmetricKey? {
        try steps.step("read the device key")
        return try base.deviceKey()
    }

    func makeNewDeviceKey() throws -> SymmetricKey {
        try steps.step("make a device key")
        return try base.makeNewDeviceKey()
    }

    func removeDeviceKey() throws {
        try steps.step("remove the device key")
        try base.removeDeviceKey()
    }
}
