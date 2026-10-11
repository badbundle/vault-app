import Foundation
import FoundationExtensions
import Security
import TestHelpers
import Testing
import VaultCore
@testable import VaultFeed

/// Where the Mac app keeps the codes it hands its widgets, and how it takes them back (G98).
struct WidgetCodeHandoffStoreTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func publish_isTheCurrentHandoff() throws {
        let sut = makeSUT()
        let handoff = anyHandoff()

        try sut.store.publish(handoff)

        #expect(sut.store.current(at: now) == handoff)
    }

    @Test
    func current_withNothingPublished_isNothing() {
        let sut = makeSUT()

        #expect(sut.store.current(at: now) == nil)
    }

    @Test
    func withdraw_deletesTheCodes() throws {
        let sut = makeSUT()
        try sut.store.publish(anyHandoff())

        try sut.store.withdraw()

        #expect(sut.store.current(at: now) == nil)
        #expect(sut.keychain.data == nil)
    }

    /// The keychain item can't always be deleted at once, as while the Mac locks. Then it's replaced with one that has
    /// no codes, and has already expired.
    @Test
    func withdraw_codesNotDeleted_leavesNoneInTheirPlace() throws {
        let sut = makeSUT()
        try sut.store.publish(anyHandoff())
        sut.keychain.failToRemove()

        try sut.store.withdraw()

        let left = try JSONDecoder().decode(WidgetCodeHandoff.self, from: #require(sut.keychain.data))
        #expect(left.items.isEmpty)
        #expect(left.expiresAt <= now)
        #expect(sut.store.current(at: now) == nil)
    }

    /// Neither can be done, so it says so: the codes run out by themselves, within the handoff's window.
    @Test
    func withdraw_codesNeitherDeletedNorReplaced_throws() throws {
        let sut = makeSUT()
        let handoff = anyHandoff()
        try sut.store.publish(handoff)
        sut.keychain.failToRemove()
        sut.keychain.failToSave()

        #expect(throws: InMemoryWidgetKeychainItem.Failure.self) {
            try sut.store.withdraw()
        }
        #expect(sut.store.current(at: handoff.expiresAt) == nil)
    }

    @Test
    func current_onceItsExpired_isNothing() throws {
        let sut = makeSUT()
        let handoff = anyHandoff()
        try sut.store.publish(handoff)

        #expect(sut.store.current(at: handoff.expiresAt.addingTimeInterval(-1)) == handoff)
        #expect(sut.store.current(at: handoff.expiresAt) == nil)
    }

    @Test
    func publish_replacesTheHandoffBefore() throws {
        let sut = makeSUT()
        try sut.store.publish(anyHandoff())
        let newer = anyHandoff()

        try sut.store.publish(newer)

        #expect(sut.store.current(at: now) == newer)
    }

    // MARK: - Keychain

    /// The keychain itself isn't available to these hostless tests, so they check what `WidgetKeychainItem` would ask
    /// it for. `MacAppKeychainTests` checks the app can keep items in the widgets' group.
    @Test
    func keychainItem_neverSyncsAndIsInTheDataProtectionKeychain() {
        let query = WidgetKeychainItem(accessGroup: "group.any", service: "service", accessibility: "any").itemQuery

        #expect(query[kSecAttrSynchronizable as String] as? Bool == false)
        #expect(query[kSecUseDataProtectionKeychain as String] as? Bool == true)
        #expect(query[kSecAttrAccessGroup as String] as? String == "group.any")
        #expect(query[kSecAttrService as String] as? String == "service")
    }

    @Test
    func codes_areReadableOnlyWhileUnlockedAndOnlyOnThisDevice() {
        let attributes = WidgetKeychainItem.codes.attributes(for: Data([1, 2, 3]))

        #expect(attributes[kSecAttrAccessible as String] as? String
            == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        #expect(attributes[kSecValueData as String] as? Data == Data([1, 2, 3]))
        #expect(WidgetKeychainItem.codes.service == VaultIdentifiers.SecureStorageKey.widgetCodes.keychainService)
    }

    @Test
    func items_areInTheWidgetsOwnGroup() {
        #if os(macOS)
        #expect(WidgetKeychainItem.codes.accessGroup == "442P244AFS.com.badbundle.vault.widgets")
        #expect(WidgetKeychainItem.copiedCode.accessGroup == "442P244AFS.com.badbundle.vault.widgets")
        #else
        // The iOS app never stores them, and has no such group.
        #expect(WidgetKeychainItem.codes.accessGroup == nil)
        #expect(WidgetKeychainItem.copiedCode.accessGroup == nil)
        #endif
    }
}

// MARK: - Helpers

extension WidgetCodeHandoffStoreTests {
    private struct SUT {
        var store: WidgetCodeHandoffStore
        var keychain: InMemoryWidgetKeychainItem
    }

    private func makeSUT() -> SUT {
        let keychain = InMemoryWidgetKeychainItem()
        return SUT(store: WidgetCodeHandoffStore(keychain: keychain), keychain: keychain)
    }

    private func anyHandoff() -> WidgetCodeHandoff {
        WidgetCodeHandoff(items: [uniqueVaultItem()], now: now)
    }
}
