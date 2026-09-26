import Foundation
import VaultFeed

/// `SecureStorage` held in memory, which behaves like the keychain as far as the stores can tell.
///
/// Items stored with `store(data:forKey:)` need user presence: loading one stands in for the user
/// authenticating, and is counted in `authenticatedRetrieveCount`. On a device, reading even their
/// attributes can fail without authenticating, so unless `canReadAttributesWithoutAuthentication`
/// is set, `attributes(key:)` throws for them, as `SecureStorageImpl` would with
/// `errSecInteractionNotAllowed`.
actor InMemorySecureStorage: SecureStorage {
    struct InteractionNotAllowed: Error {}

    private struct Item {
        var data: Data
        var needsUserPresence: Bool
    }

    private var items = [String: Item]()
    private let canReadAttributesWithoutAuthentication: Bool
    private let modificationDate: Date

    /// How many times data that needs user presence was loaded, each of which would ask the user
    /// to authenticate.
    private(set) var authenticatedRetrieveCount = 0

    init(
        canReadAttributesWithoutAuthentication: Bool = false,
        modificationDate: Date = Date(timeIntervalSince1970: 0),
    ) {
        self.canReadAttributesWithoutAuthentication = canReadAttributesWithoutAuthentication
        self.modificationDate = modificationDate
    }

    func contains(key: String) -> Bool {
        items[key] != nil
    }

    func store(data: Data, forKey key: String) {
        items[key] = Item(data: data, needsUserPresence: true)
    }

    func retrieve(key: String) -> Data? {
        guard let item = items[key] else { return nil }
        if item.needsUserPresence {
            authenticatedRetrieveCount += 1
        }
        return item.data
    }

    func storeSilent(data: Data, forKey key: String) {
        items[key] = Item(data: data, needsUserPresence: false)
    }

    /// Like the keychain, what's needed to read an item depends on how it was stored, not on how
    /// it's read.
    func retrieveSilent(key: String) -> Data? {
        retrieve(key: key)
    }

    func attributes(key: String) throws -> SecureStorageAttributes? {
        guard let item = items[key] else { return nil }
        guard !item.needsUserPresence || canReadAttributesWithoutAuthentication else {
            throw InteractionNotAllowed()
        }
        return SecureStorageAttributes(modificationDate: modificationDate)
    }

    func remove(key: String) {
        items[key] = nil
    }
}
