import Foundation
import LocalAuthentication
import Security
import Testing
@testable import VaultFeed

/// The keychain itself isn't available to these hostless tests, so they check the query that
/// `SecureStorageImpl` would run.
struct SecureStorageImplTests {
    @Test
    func attributesQuery_disallowsInteraction() throws {
        let query = SecureStorageImpl.attributesQuery(key: "any")

        let context = try #require(query[kSecUseAuthenticationContext as String] as? LAContext)
        #expect(context.interactionNotAllowed)
    }

    /// Skipping would make an item that needs authentication look missing, so it must fail instead.
    @Test
    func attributesQuery_doesNotSkipItemsNeedingAuthentication() {
        let query = SecureStorageImpl.attributesQuery(key: "any")

        #expect(query[kSecUseAuthenticationUI as String] == nil)
    }

    @Test
    func attributesQuery_matchesItemForKey() {
        let query = SecureStorageImpl.attributesQuery(key: "my-key")

        #expect(query[kSecAttrService as String] as? String == "my-key")
    }
}
