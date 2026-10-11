import Foundation
import FoundationExtensions
import VaultFeed

/// One of the widgets' keychain items in memory, as the keychain would keep it, which fails when the test says.
final class InMemoryWidgetKeychainItem: WidgetKeychainStoring {
    struct Failure: Error {}

    private struct State {
        var data: Data?
        var failsToRemove = false
        var failsToSave = false
    }

    private let state = SharedMutex(State())

    /// The bytes as they're stored now.
    var data: Data? {
        state.get { $0.data }
    }

    func failToRemove() {
        state.modify { $0.failsToRemove = true }
    }

    func failToSave() {
        state.modify { $0.failsToSave = true }
    }

    func read() throws -> Data? {
        state.get { $0.data }
    }

    func save(_ data: Data) throws {
        try state.modify { state in
            guard !state.failsToSave else { throw Failure() }
            state.data = data
        }
    }

    func remove() throws {
        try state.modify { state in
            guard !state.failsToRemove else { throw Failure() }
            state.data = nil
        }
    }
}
