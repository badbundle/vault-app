import Foundation
import TestHelpers
import Testing
import UIKit
@testable import VaultFeed
@testable import VaultiOS

/// What `VaultRoot` wires the app lock up to: the device locking, and what the app forgets when it locks.
@MainActor
struct VaultRootAppLockTests {
    private static let password = "correct horse"

    /// With the App Lock Password set, the device locking locks the app and the vault at once, even though the Require
    /// Unlock delay hasn't passed: its keys don't stay in memory while the device is locked.
    @Test
    func deviceLocking_withThePasswordSet_locksWithinTheDelay() async throws {
        let passwordService = FakeAppLockPasswordService(password: Self.password)
        let appLock = try makeAppLock(passwordService: passwordService)
        await appLock.unlock()
        await appLock.unlock(password: Self.password)
        appLock.scenePhaseDidChange(to: .background)
        #expect(!appLock.isLocked, "Within the delay")
        let notificationCenter = NotificationCenter()
        let observer = VaultRoot.lockWhenTheDeviceLocks(appLock, notificationCenter: notificationCenter)
        defer { notificationCenter.removeObserver(observer) }

        notificationCenter.post(name: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil)

        try await waitUntil { appLock.isLocked }
        await appLock.vaultLock?.value
        #expect(!passwordService.isVaultOpen)
        #expect(appLock.state == .locked(.init(step: .deviceAuthentication)))
    }

    /// Without the password, there are no keys to take out of memory, and the delay stands.
    @Test
    func deviceLocking_withoutThePassword_leavesItToTheDelay() async throws {
        let appLock = try makeAppLock(passwordService: nil)
        await appLock.unlock()
        appLock.scenePhaseDidChange(to: .background)
        let notificationCenter = NotificationCenter()
        let observer = VaultRoot.lockWhenTheDeviceLocks(appLock, notificationCenter: notificationCenter)
        defer { notificationCenter.removeObserver(observer) }

        notificationCenter.post(name: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil)
        try await Task.sleep(for: .milliseconds(100))

        #expect(!appLock.isLocked)
    }

    /// What the app lock clears as it locks: the backup password straight away, then everything read from the vault,
    /// and the search, which might be a search passphrase.
    @Test
    func purgeSensitiveDataForAppLock_forgetsEverythingReadFromTheVault() async throws {
        let tag = anyVaultItemTag()
        let store = VaultStoreStub()
        store.retrieveHandler = { _ in .init(items: [uniqueVaultItem(), uniqueVaultItem()]) }
        let tagStore = VaultTagStoreStub()
        tagStore.retrieveTagsHandler = { [tag] }
        let backupPasswordStore = BackupPasswordStoreMock()
        backupPasswordStore.fetchPasswordHandler = {
            DerivedEncryptionKey(key: .random(), salt: Data(), keyDervier: .testing)
        }
        let dataModel = anyVaultDataModel(
            vaultStore: store,
            vaultTagStore: tagStore,
            backupPasswordStore: backupPasswordStore,
        )
        let itemCache = VaultItemCacheMock()
        dataModel.itemCaches.append(itemCache)
        await dataModel.reloadData()
        await dataModel.loadBackupPassword()
        dataModel.itemsSearchQuery = "a search passphrase"
        dataModel.toggleFiltering(tag: tag.id)
        #expect(dataModel.items.count == 2)
        #expect(dataModel.backupPassword.fetchedPassword != nil)

        let purge = VaultRoot.purgeSensitiveDataForAppLock(dataModel)

        #expect(dataModel.backupPassword == .notFetched, "Straight away")
        await purge.value
        #expect(dataModel.items.isEmpty)
        #expect(!dataModel.hasVisibleItems)
        #expect(dataModel.allTags.isEmpty)
        #expect(dataModel.itemsSearchQuery.isEmpty)
        #expect(dataModel.itemsFilteringByTags.isEmpty)
        #expect(itemCache.vaultItemCacheClearAllCallCount == 1)
    }
}

// MARK: - Helpers

extension VaultRootAppLockTests {
    /// The lock on, with Require Unlock at 15 minutes.
    private func makeAppLock(passwordService: (any AppLockPasswordService)?) throws -> AppLockService {
        let settings = try AppLockSettingsStore(userDefaults: .nonPersistent())
        settings.isEnabled = true
        settings.delay = .fifteenMinutes
        return AppLockService(
            settings: settings,
            authenticationService: DeviceAuthenticationService(policy: .alwaysAllow),
            passwordService: passwordService,
            purgeSensitiveData: {},
        )
    }

    /// Waits for the notification, which is delivered on the main queue, up to a couple of seconds.
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("Timed out waiting")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
