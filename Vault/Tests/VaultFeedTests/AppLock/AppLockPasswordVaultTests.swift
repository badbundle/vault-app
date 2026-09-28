import Foundation
import TestHelpers
import Testing
@testable import VaultFeed

/// The app lock over a real vault with the App Lock Password, and the data model the app shows it with: what locking,
/// the device locking and the Require Unlock delay do to the vault and what the app holds of it.
@MainActor
struct AppLockPasswordVaultTests {
    private typealias SUT = EncryptedVaultPasswordServiceTests.SUT
    private static let password = "correct horse"

    /// The device locking locks the vault and forgets what was read from it: it takes the password to read it again.
    @Test
    func deviceWillLock_locksTheVaultAndForgetsWhatWasReadFromIt() async throws {
        try await withTemporaryDirectory { directory in
            let sut = try await SUT(directory: directory, delay: .fifteenMinutes)
            let item = try await sut.insertItem()
            #expect(try await sut.appLock.setPassword(Self.password))
            await sut.dataModel.reloadData()
            sut.dataModel.itemsSearchQuery = "a search passphrase"
            #expect(sut.dataModel.items.map(\.id) == [item])

            sut.appLock.deviceWillLock()
            await sut.appLock.vaultLock?.value

            #expect(sut.appLock.isLocked)
            #expect(await sut.session.isLocked)
            #expect(sut.dataModel.items.isEmpty)
            #expect(sut.dataModel.itemsSearchQuery.isEmpty)
            await sut.dataModel.reloadData()
            #expect(sut.dataModel.items.isEmpty)
            #expect(try await sut.itemIDs().isEmpty)

            await sut.appLock.unlock()
            #expect(sut.appLock.state == .locked(.init(step: .password)))
            await sut.appLock.unlock(password: Self.password)
            #expect(sut.appLock.state == .unlocked)
            #expect(try await sut.itemIDs() == [item])
        }
    }

    /// Gone to the background within Require Unlock's delay, the device locking locks the vault all the same.
    @Test
    func deviceWillLock_withinTheRequireUnlockDelay_locksTheVault() async throws {
        try await withTemporaryDirectory { directory in
            let sut = try await SUT(directory: directory, delay: .fifteenMinutes)
            #expect(try await sut.appLock.setPassword(Self.password))
            sut.appLock.scenePhaseDidChange(to: .background)
            #expect(!sut.appLock.isLocked)
            #expect(await !sut.session.isLocked)

            sut.appLock.deviceWillLock()
            await sut.appLock.vaultLock?.value

            #expect(sut.appLock.isLocked)
            #expect(await sut.session.isLocked)
        }
    }

    /// Back within Require Unlock's delay, the vault stays open, with its keys, and nothing asks to unlock it.
    @Test
    func requireUnlockDelay_backWithinIt_leavesTheVaultOpen() async throws {
        try await withTemporaryDirectory { directory in
            let sut = try await SUT(directory: directory, delay: .oneMinute)
            let item = try await sut.insertItem()
            #expect(try await sut.appLock.setPassword(Self.password))

            sut.appLock.scenePhaseDidChange(to: .background)
            sut.keychain.attemptClock.advance(by: .seconds(59))
            sut.appLock.scenePhaseDidChange(to: .inactive)
            sut.appLock.scenePhaseDidChange(to: .active)

            #expect(sut.appLock.state == .unlocked)
            #expect(sut.appLock.automaticUnlock == nil)
            #expect(await !sut.session.isLocked)
            #expect(try await sut.itemIDs() == [item])
        }
    }

    /// Back after Require Unlock's delay, the vault is locked, and it takes the password as well as device
    /// authentication to open it.
    @Test
    func requireUnlockDelay_backAfterIt_locksTheVaultAndAsksForThePassword() async throws {
        try await withTemporaryDirectory { directory in
            let sut = try await SUT(directory: directory, delay: .oneMinute)
            let item = try await sut.insertItem()
            #expect(try await sut.appLock.setPassword(Self.password))
            await sut.dataModel.reloadData()

            sut.appLock.scenePhaseDidChange(to: .background)
            sut.keychain.attemptClock.advance(by: .seconds(60))
            sut.appLock.scenePhaseDidChange(to: .active)
            await sut.appLock.vaultLock?.value

            #expect(sut.appLock.isLocked)
            #expect(await sut.session.isLocked)
            #expect(sut.dataModel.items.isEmpty)
            // Device authentication is asked for as the app comes back, then the password.
            await sut.appLock.automaticUnlock?.value
            #expect(sut.appLock.state == .locked(.init(step: .password)))
            await sut.appLock.unlock(password: Self.password)
            #expect(sut.appLock.state == .unlocked)
            #expect(try await sut.itemIDs() == [item])
        }
    }

    /// A launch starts locked however long the delay, even when the vault was left open.
    @Test
    func relaunch_withTheVaultLeftOpen_startsLockedWhateverTheDelay() async throws {
        try await withTemporaryDirectory { directory in
            let keychain = try EncryptedVaultPasswordServiceTests.Keychain()
            let before = try await SUT(directory: directory, keychain: keychain, delay: .fifteenMinutes)
            let item = try await before.insertItem()
            #expect(try await before.appLock.setPassword(Self.password))
            #expect(before.appLock.state == .unlocked)

            let sut = try await SUT(directory: directory, keychain: keychain, mode: .password, delay: .fifteenMinutes)

            #expect(sut.appLock.state == .locked(.init(step: .deviceAuthentication)))
            #expect(await sut.session.isLocked)
            await sut.appLock.unlock()
            await sut.appLock.unlock(password: Self.password)
            #expect(try await sut.itemIDs() == [item])
        }
    }
}
