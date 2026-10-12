import Foundation
import FoundationExtensions
import Security
@testable import VaultFeed

/// The data protection keychain's password items in memory, kept apart by access group and service, as the keychain
/// keeps them, for the calls `SharedKeychainItem` makes. Any call can be made to fail, and something can be done just
/// before one, as another process could.
final class InMemoryKeychain: KeychainCalls {
    struct Item: Equatable, Sendable {
        var data: Data
        var accessible = kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String
        var synchronizable = false
    }

    /// One of the calls, and the access group it names.
    enum Call: Hashable, Sendable {
        case copy(group: String?)
        case add(group: String?)
        case update(group: String?)
        case delete(group: String?)
    }

    private struct State {
        /// By access group, then service.
        var items: [String?: [String: Item]] = [:]
        var failures: [Call: OSStatus] = [:]
        var calls: [Call] = []
    }

    private let state = SharedMutex(State())
    private let beforeCall = SharedMutex<(@Sendable (Call) -> Void)?>(nil)

    /// Every call made, in order.
    var calls: [Call] {
        state.get { $0.calls }
    }

    func item(_ key: VaultIdentifiers.SecureStorageKey, in group: String?) -> Item? {
        state.get { $0.items[group]?[key.keychainService] }
    }

    func set(_ item: Item?, for key: VaultIdentifiers.SecureStorageKey, in group: String?) {
        state.modify { $0.items[group, default: [:]][key.keychainService] = item }
    }

    /// Makes every call like `call` answer `status`, until it's set to `nil`.
    func fail(_ call: Call, with status: OSStatus? = errSecIO) {
        state.modify { $0.failures[call] = status }
    }

    /// Runs `action` just before each call is answered, as another process could act just then.
    func beforeEachCall(_ action: @escaping @Sendable (Call) -> Void) {
        beforeCall.modify { $0 = action }
    }

    // MARK: - KeychainCalls

    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, result: AnyObject?) {
        let address = Address(query)
        let returnsData = query[kSecReturnData as String] as? Bool ?? false
        let returnsAttributes = query[kSecReturnAttributes as String] as? Bool ?? false
        let found = answer(.copy(group: address.group)) { state -> (OSStatus, Item?) in
            guard let item = state.items[address.group]?[address.service],
                  address.synchronizable.map({ $0 == item.synchronizable }) ?? true
            else {
                return (errSecItemNotFound, nil)
            }
            return (errSecSuccess, item)
        }
        guard found.0 == errSecSuccess, let item = found.1 else { return (found.0, nil) }
        if returnsAttributes {
            var attributes: [String: Any] = [
                kSecAttrService as String: address.service,
                kSecAttrAccessible as String: item.accessible,
                kSecAttrSynchronizable as String: item.synchronizable,
            ]
            attributes[kSecAttrAccessGroup as String] = address.group
            attributes[kSecValueData as String] = returnsData ? item.data : nil
            return (errSecSuccess, attributes as NSDictionary)
        }
        return (errSecSuccess, returnsData ? item.data as NSData : nil)
    }

    func add(_ item: [String: Any]) -> OSStatus {
        let address = Address(item)
        let new = Item(
            data: item[kSecValueData as String] as? Data ?? Data(),
            accessible: item[kSecAttrAccessible as String] as? String ?? kSecAttrAccessibleWhenUnlocked as String,
            synchronizable: address.synchronizable ?? false,
        )
        return answer(.add(group: address.group)) { state in
            guard state.items[address.group]?[address.service] == nil else { return errSecDuplicateItem }
            state.items[address.group, default: [:]][address.service] = new
            return errSecSuccess
        }
    }

    func update(_ query: [String: Any], with attributes: [String: Any]) -> OSStatus {
        let address = Address(query)
        let data = attributes[kSecValueData as String] as? Data
        let accessible = attributes[kSecAttrAccessible as String] as? String
        return answer(.update(group: address.group)) { state in
            guard var item = state.items[address.group]?[address.service] else { return errSecItemNotFound }
            item.data = data ?? item.data
            item.accessible = accessible ?? item.accessible
            state.items[address.group]?[address.service] = item
            return errSecSuccess
        }
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        let address = Address(query)
        return answer(.delete(group: address.group)) { state in
            // Without a group, the keychain deletes the item from every group the caller has.
            let groups = address.group.map { [$0] } ?? Array(state.items.keys)
            var deleted = false
            for group in groups where state.items[group]?[address.service] != nil {
                state.items[group]?[address.service] = nil
                deleted = true
            }
            return deleted ? errSecSuccess : errSecItemNotFound
        }
    }

    /// Records `call`, runs whatever's to happen just before it, then answers it with its failure, or with `body`.
    private func answer<T: Sendable>(
        _ call: Call,
        failure: @Sendable (OSStatus) -> T,
        _ body: @Sendable (inout State) -> T,
    ) -> T {
        beforeCall.get { $0 }?(call)
        return state.modify { state in
            state.calls.append(call)
            if let status = state.failures[call] {
                return failure(status)
            }
            return body(&state)
        }
    }

    private func answer(_ call: Call, _ body: @Sendable (inout State) -> OSStatus) -> OSStatus {
        answer(call, failure: { $0 }, body)
    }

    private func answer(
        _ call: Call,
        _ body: @Sendable (inout State) -> (OSStatus, Item?),
    ) -> (OSStatus, Item?) {
        answer(call, failure: { ($0, nil) }, body)
    }

    /// Where a query or item is in the keychain.
    private struct Address: Sendable {
        var group: String?
        var service: String
        var synchronizable: Bool?

        init(_ query: [String: Any]) {
            group = query[kSecAttrAccessGroup as String] as? String
            service = query[kSecAttrService as String] as? String ?? ""
            synchronizable = query[kSecAttrSynchronizable as String] as? Bool
        }
    }
}
