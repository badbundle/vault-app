import Foundation
import FoundationExtensions
import Security
import Testing
@testable import VaultFeed

/// The keychain itself isn't available to these hostless tests, so they run `SharedKeychainItem` on one in memory,
/// which keeps items apart by access group, as the keychain does.
struct SharedKeychainItemTests {
    private let keychain = InMemoryKeychain()
    private static let key = VaultIdentifiers.SecureStorageKey.vaultWrapStamp
    private static let shared = VaultSharedStorage.keychainGroupID
    private static let appGroup = VaultSharedStorage.appGroupID
    private static let old = InMemoryKeychain.Item(data: Data("old".utf8))
    private static let new = InMemoryKeychain.Item(data: Data("new".utf8))

    // MARK: - Groups

    /// Only the app and the AutoFill extension have the shared group, not the widget extension, which has the App
    /// Group's (VAULT-129).
    @Test
    func init_keepsTheItemInTheSharedGroupAndMovesItFromTheAppGroups() {
        let sut = SharedKeychainItem(key: Self.key)

        #expect(sut.accessGroup == "442P244AFS.com.badbundle.vault.shared")
        #expect(sut.formerAccessGroup == VaultSharedStorage.appGroupID)
        #expect(VaultSharedStorage.keychainGroupID != VaultSharedStorage.appGroupID)
    }

    @Test
    func query_isAPasswordItemUnderTheKeysServiceThatNeverSyncs() {
        let query = makeSUT().query(in: "group.any")

        #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(query[kSecAttrService as String] as? String == Self.key.rawValue)
        #expect(query[kSecAttrAccessGroup as String] as? String == "group.any")
        #expect(query[kSecAttrSynchronizable as String] as? Bool == false)
        #expect(query[kSecUseDataProtectionKeychain as String] as? Bool == true)
    }

    // MARK: - Reading

    @Test
    func data_inBothGroups_isTheSharedGroups() throws {
        keychain.set(Self.old, for: Self.key, in: Self.appGroup)
        keychain.set(Self.new, for: Self.key, in: Self.shared)

        #expect(try makeSUT().data() == Self.new.data)
    }

    /// Until it's moved, it's read where an earlier version left it.
    @Test
    func data_onlyInTheAppGroup_isReadFromThere() throws {
        keychain.set(Self.old, for: Self.key, in: Self.appGroup)

        #expect(try makeSUT().data() == Self.old.data)
    }

    @Test
    func data_inNeitherGroup_isNil() throws {
        #expect(try makeSUT().data() == nil)
    }

    /// A move that finishes between the reads of the two groups leaves the item where the last read finds it.
    @Test
    func data_movedBetweenTheReads_isFound() throws {
        keychain.set(Self.old, for: Self.key, in: Self.appGroup)
        let keychain = keychain
        keychain.beforeEachCall { call in
            guard call == .copy(group: Self.appGroup), keychain.item(Self.key, in: Self.shared) == nil else { return }
            keychain.set(Self.old, for: Self.key, in: Self.shared)
            keychain.set(nil, for: Self.key, in: Self.appGroup)
        }

        #expect(try makeSUT().data() == Self.old.data)
    }

    /// A group that can't be read, as while the device is locked, isn't taken to hold nothing.
    @Test
    func data_sharedGroupUnreadable_throwsWithoutReadingTheAppGroup() {
        keychain.set(Self.old, for: Self.key, in: Self.appGroup)
        keychain.fail(.copy(group: Self.shared), with: errSecInteractionNotAllowed)

        #expect(throws: (any Error).self) {
            try makeSUT().data()
        }
        #expect(!keychain.calls.contains(.copy(group: Self.appGroup)))
    }

    @Test
    func data_appGroupUnreadable_throws() {
        keychain.fail(.copy(group: Self.appGroup), with: errSecInteractionNotAllowed)

        #expect(throws: (any Error).self) {
            try makeSUT().data()
        }
    }

    // MARK: - Writing

    @Test
    func save_writesOnlyTheSharedGroup() throws {
        keychain.set(Self.old, for: Self.key, in: Self.appGroup)

        try makeSUT().save(attributes(Self.new))

        #expect(keychain.item(Self.key, in: Self.shared) == Self.new)
        #expect(keychain.item(Self.key, in: Self.appGroup) == Self.old)
        #expect(try makeSUT().data() == Self.new.data)
    }

    /// The item is updated in place, never deleted and added again, so there's never a moment without it.
    @Test
    func save_overAnItem_updatesItInPlace() throws {
        keychain.set(Self.old, for: Self.key, in: Self.shared)

        try makeSUT().save(attributes(Self.new))

        #expect(keychain.item(Self.key, in: Self.shared) == Self.new)
        #expect(keychain.calls == [.update(group: Self.shared)])
    }

    @Test
    func add_whenTheSharedGroupHasTheItem_changesNothing() throws {
        keychain.set(Self.old, for: Self.key, in: Self.shared)

        #expect(try makeSUT().add(attributes(Self.new)) == false)
        #expect(keychain.item(Self.key, in: Self.shared) == Self.old)
    }

    @Test
    func add_whenNeitherGroupHasTheItem_addsItToTheSharedGroup() throws {
        #expect(try makeSUT().add(attributes(Self.new)) == true)
        #expect(keychain.item(Self.key, in: Self.shared) == Self.new)
        #expect(keychain.item(Self.key, in: Self.appGroup) == nil)
    }

    // MARK: - Removing

    @Test
    func remove_deletesTheItemFromBothGroups() throws {
        keychain.set(Self.old, for: Self.key, in: Self.appGroup)
        keychain.set(Self.new, for: Self.key, in: Self.shared)

        try makeSUT().remove()

        #expect(keychain.item(Self.key, in: Self.appGroup) == nil)
        #expect(keychain.item(Self.key, in: Self.shared) == nil)
        #expect(try makeSUT().data() == nil)
    }

    @Test
    func remove_withNothingToRemove_succeeds() throws {
        try makeSUT().remove()
    }

    /// If deleting the App Group's fails, the shared group's is still there, and reads find the item's current value.
    @Test
    func remove_failingInTheAppGroup_keepsTheCurrentValue() throws {
        keychain.set(Self.old, for: Self.key, in: Self.appGroup)
        keychain.set(Self.new, for: Self.key, in: Self.shared)
        keychain.fail(.delete(group: Self.appGroup))

        #expect(throws: (any Error).self) {
            try makeSUT().remove()
        }
        keychain.fail(.delete(group: Self.appGroup), with: nil)
        #expect(try makeSUT().data() == Self.new.data)
    }

    /// The App Group's is deleted first, so if deleting the shared group's fails, reads still find the current value,
    /// never the older one.
    @Test
    func remove_failingInTheSharedGroup_neverLeavesTheOlderValue() throws {
        keychain.set(Self.old, for: Self.key, in: Self.appGroup)
        keychain.set(Self.new, for: Self.key, in: Self.shared)
        keychain.fail(.delete(group: Self.shared))

        #expect(throws: (any Error).self) {
            try makeSUT().remove()
        }
        keychain.fail(.delete(group: Self.shared), with: nil)
        #expect(keychain.item(Self.key, in: Self.appGroup) == nil)
        #expect(try makeSUT().data() == Self.new.data)
    }

    // MARK: - Moving

    @Test
    func move_withNothingInTheAppGroup_changesNothing() throws {
        try makeSUT().moveFromTheAppGroup()

        #expect(keychain.item(Self.key, in: Self.shared) == nil)
        #expect(keychain.calls == [.copy(group: Self.appGroup)])
    }

    /// The copy has the same bytes and accessibility, and never syncs.
    @Test(arguments: [
        kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String,
        kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String,
        kSecAttrAccessibleAfterFirstUnlock as String,
    ])
    func move_fromTheAppGroup_keepsTheItemAsItWas(accessible: String) throws {
        let item = InMemoryKeychain.Item(data: Data("item".utf8), accessible: accessible)
        keychain.set(item, for: Self.key, in: Self.appGroup)

        try makeSUT().moveFromTheAppGroup()

        #expect(keychain.item(Self.key, in: Self.shared) == item)
        #expect(keychain.item(Self.key, in: Self.appGroup) == nil)
    }

    /// Only once the copy reads back is the App Group's deleted.
    @Test
    func move_deletesTheAppGroupsLast() throws {
        keychain.set(Self.old, for: Self.key, in: Self.appGroup)

        try makeSUT().moveFromTheAppGroup()

        #expect(keychain.calls == [
            .copy(group: Self.appGroup),
            .add(group: Self.shared),
            .copy(group: Self.shared),
            .delete(group: Self.appGroup),
        ])
    }

    /// The shared group's is the item's current value: everything writes there, having read it first. Or another
    /// process has just moved it.
    @Test(arguments: [old, new])
    func move_whenBothGroupsHoldIt_keepsTheSharedGroupsAndDeletesTheAppGroups(shared: InMemoryKeychain.Item) throws {
        keychain.set(Self.old, for: Self.key, in: Self.appGroup)
        keychain.set(shared, for: Self.key, in: Self.shared)

        try makeSUT().moveFromTheAppGroup()

        #expect(keychain.item(Self.key, in: Self.shared) == shared)
        #expect(keychain.item(Self.key, in: Self.appGroup) == nil)
    }

    /// The AutoFill extension moving it at the same moment as the app.
    @Test
    func move_whenAnotherProcessAddsItMeanwhile_keepsTheirsAndDeletesTheAppGroups() throws {
        keychain.set(Self.old, for: Self.key, in: Self.appGroup)
        let keychain = keychain
        keychain.beforeEachCall { call in
            guard call == .add(group: Self.shared), keychain.item(Self.key, in: Self.shared) == nil else { return }
            keychain.set(Self.old, for: Self.key, in: Self.shared)
        }

        try makeSUT().moveFromTheAppGroup()

        #expect(keychain.item(Self.key, in: Self.shared) == Self.old)
        #expect(keychain.item(Self.key, in: Self.appGroup) == nil)
    }

    @Test
    func move_whenAnotherProcessDeletesTheAppGroupsMeanwhile_succeeds() throws {
        keychain.set(Self.old, for: Self.key, in: Self.appGroup)
        let keychain = keychain
        keychain.beforeEachCall { call in
            guard call == .delete(group: Self.appGroup) else { return }
            keychain.set(nil, for: Self.key, in: Self.appGroup)
        }

        try makeSUT().moveFromTheAppGroup()

        #expect(keychain.item(Self.key, in: Self.shared) == Self.old)
        #expect(keychain.item(Self.key, in: Self.appGroup) == nil)
    }

    @Test
    func move_twice_isTheSameAsOnce() throws {
        keychain.set(Self.old, for: Self.key, in: Self.appGroup)

        try makeSUT().moveFromTheAppGroup()
        try makeSUT().moveFromTheAppGroup()

        #expect(keychain.item(Self.key, in: Self.shared) == Self.old)
        #expect(keychain.item(Self.key, in: Self.appGroup) == nil)
    }

    /// Whichever step fails, the App Group's item stays, still read as the item, and the next move finishes.
    @Test(arguments: [
        InMemoryKeychain.Call.copy(group: appGroup),
        .add(group: shared),
        .copy(group: shared),
        .delete(group: appGroup),
    ])
    func move_failingAtAnyStep_keepsTheAppGroupsItemForTheNextMove(failing: InMemoryKeychain.Call) throws {
        keychain.set(Self.old, for: Self.key, in: Self.appGroup)
        keychain.fail(failing)

        #expect(throws: (any Error).self) {
            try makeSUT().moveFromTheAppGroup()
        }

        #expect(keychain.item(Self.key, in: Self.appGroup) == Self.old)
        keychain.fail(failing, with: nil)
        #expect(try makeSUT().data() == Self.old.data)
        try makeSUT().moveFromTheAppGroup()
        #expect(keychain.item(Self.key, in: Self.shared) == Self.old)
        #expect(keychain.item(Self.key, in: Self.appGroup) == nil)
    }

    /// A copy that doesn't read back as it was added keeps the App Group's. Here something saved a newer value
    /// straight after the copy was added, which the next move keeps.
    @Test
    func move_copyNotReadingBackAsAdded_keepsTheAppGroupsUntilTheNextMove() throws {
        keychain.set(Self.old, for: Self.key, in: Self.appGroup)
        let keychain = keychain
        keychain.beforeEachCall { call in
            guard call == .copy(group: Self.shared),
                  keychain.item(Self.key, in: Self.shared) == Self.old else { return }
            keychain.set(Self.new, for: Self.key, in: Self.shared)
        }

        #expect(throws: SharedKeychainItem.MoveError.copyDoesNotMatch) {
            try makeSUT().moveFromTheAppGroup()
        }
        #expect(keychain.item(Self.key, in: Self.appGroup) == Self.old)
        #expect(try makeSUT().data() == Self.new.data)

        try makeSUT().moveFromTheAppGroup()
        #expect(keychain.item(Self.key, in: Self.shared) == Self.new)
        #expect(keychain.item(Self.key, in: Self.appGroup) == nil)
    }

    @Test
    func move_sharedGroupsWithAnotherAccessibility_keepsTheAppGroups() throws {
        keychain.set(Self.old, for: Self.key, in: Self.appGroup)
        let other = InMemoryKeychain.Item(data: Self.old.data, accessible: kSecAttrAccessibleAfterFirstUnlock as String)
        keychain.set(other, for: Self.key, in: Self.shared)

        #expect(throws: SharedKeychainItem.MoveError.copyDoesNotMatch) {
            try makeSUT().moveFromTheAppGroup()
        }
        #expect(keychain.item(Self.key, in: Self.appGroup) == Self.old)
    }

    @Test
    func move_sharedGroupsSyncing_keepsTheAppGroups() throws {
        keychain.set(Self.old, for: Self.key, in: Self.appGroup)
        let keychain = keychain
        keychain.beforeEachCall { call in
            guard call == .copy(group: Self.shared) else { return }
            var syncing = Self.old
            syncing.synchronizable = true
            keychain.set(syncing, for: Self.key, in: Self.shared)
        }

        #expect(throws: (any Error).self) {
            try makeSUT().moveFromTheAppGroup()
        }
        #expect(keychain.item(Self.key, in: Self.appGroup) == Self.old)
    }

    /// The app and the AutoFill extension moving it at once, from many threads, leave one copy, in the shared group.
    @Test
    func move_fromManyProcessesAtOnce_leavesOneCopyInTheSharedGroup() async throws {
        for _ in 0 ..< 50 {
            let keychain = InMemoryKeychain()
            keychain.set(Self.old, for: Self.key, in: Self.appGroup)
            let sut = SharedKeychainItem(key: Self.key, keychain: keychain)

            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0 ..< 4 {
                    group.addTask {
                        try sut.moveFromTheAppGroup()
                        // Whenever it's read, it's found, in one group or the other.
                        #expect(try sut.data() == Self.old.data)
                    }
                }
                try await group.waitForAll()
            }

            try sut.moveFromTheAppGroup()
            #expect(keychain.item(Self.key, in: Self.shared) == Self.old)
            #expect(keychain.item(Self.key, in: Self.appGroup) == nil)
        }
    }

    @Test
    func isInTheAppGroup_isWhetherItsStillThere() throws {
        #expect(try makeSUT().isInTheAppGroup() == false)
        keychain.set(Self.old, for: Self.key, in: Self.appGroup)
        #expect(try makeSUT().isInTheAppGroup() == true)
        try makeSUT().moveFromTheAppGroup()
        #expect(try makeSUT().isInTheAppGroup() == false)
    }

    // MARK: - Helpers

    private func makeSUT() -> SharedKeychainItem {
        SharedKeychainItem(key: Self.key, keychain: keychain)
    }

    private func attributes(_ item: InMemoryKeychain.Item) -> [String: Any] {
        [
            kSecValueData as String: item.data,
            kSecAttrAccessible as String: item.accessible,
        ]
    }
}
