import AppKit
import Foundation
import TestHelpers
import Testing
import VaultCore
@testable import VaultFeed
@testable import VaultMac

/// The Mac AutoFill sheet, under the iOS AutoFill rules.
@MainActor
struct VaultMacAutofillModelTests {
    @Test
    func passwordSet_asksForThePasswordAfterTouchIDOrTheMacsPassword() async throws {
        let env = try Environment()

        await env.sut.prepareToUnlock()
        #expect(env.sut.availability == .available)
        await env.sut.appLock.unlock()
        guard case let .locked(state) = env.sut.appLock.state else {
            Issue.record("Expected the sheet to stay locked for the password, got \(env.sut.appLock.state)")
            return
        }
        #expect(state.step == .password)

        await env.sut.appLock.unlock(password: "correct horse battery")

        #expect(!env.sut.appLock.isLocked)
    }

    @Test
    func wrongPassword_staysLocked() async throws {
        let env = try Environment()
        await env.sut.prepareToUnlock()
        await env.sut.appLock.unlock()

        await env.sut.appLock.unlock(password: "not the password")

        #expect(env.sut.appLock.isLocked)
    }

    @Test(arguments: [VaultAccessMode.plain, .deviceKey])
    func vaultNotSetUp_sendsTheUserToVault(mode: VaultAccessMode) async throws {
        let env = try Environment(mode: mode)

        await env.sut.prepareToUnlock()

        #expect(env.sut.availability == .needsTheApp(.notSetUp))
    }

    @Test
    func vaultUnavailable_sendsTheUserToVault() async throws {
        let env = try Environment(mode: .unavailable)

        await env.sut.prepareToUnlock()

        #expect(env.sut.availability == .needsTheApp(.unavailable))
    }

    @Test
    func notEnoughMemory_sendsTheUserToVault() async throws {
        let env = try Environment()
        env.vault.hasHeadroom = false

        await env.sut.prepareToUnlock()

        #expect(env.sut.availability == .needsTheApp(.notEnoughMemory))
    }

    @Test
    func theMacLocking_locksTheSheetAndTheVault() async throws {
        let env = try await Environment.unlocked()
        let locks = env.vault.lockCount

        env.sut.deviceWillLock()
        await env.sut.waitForTheVault()

        #expect(env.sut.appLock.isLocked)
        #expect(env.vault.lockCount > locks)
    }

    /// As the app locks when another comes to the front.
    @Test
    func userLeaving_locksTheSheetAndTheVault() async throws {
        let env = try await Environment.unlocked()
        let locks = env.vault.lockCount

        env.sut.userDidLeave()
        await env.sut.waitForTheVault()

        #expect(env.sut.appLock.isLocked)
        #expect(env.vault.lockCount > locks)
    }

    /// The app's first launch set the password after the sheet's lock was made.
    @Test
    func passwordNotSetYet_sendsTheUserToVault() async throws {
        let env = try Environment(password: nil)

        await env.sut.prepareToUnlock()

        #expect(env.sut.availability == .needsTheApp(.notSetUp))
    }

    @Test
    func endRequest_locksTheVault() async throws {
        let env = try await Environment.unlocked()
        let locks = env.vault.lockCount

        await env.sut.endRequest()

        #expect(env.sut.appLock.isLocked)
        #expect(env.vault.lockCount > locks)
    }

    @Test
    func codes_neverOfferALockedOrHiddenCode() async throws {
        let env = try await Environment.unlocked()
        _ = try await env.store.insert(item: MacTestItems.code(issuer: "Offered").makeWritable())
        _ = try await env.store.insert(item: MacTestItems.code(issuer: "Locked", lockState: .lockedWithNativeSecurity)
            .makeWritable())
        var hidden = MacTestItems.code(issuer: "Hidden")
        hidden.metadata.visibility = .onlySearch
        hidden.metadata.searchableLevel = .onlyPassphrase
        _ = try await env.store.insert(item: hidden.makeWritable())
        _ = try await env.store.insert(item: MacTestItems.note().makeWritable())
        _ = try await env.store
            .insert(item: MacTestItems.code(issuer: "Counter", type: .hotp(counter: 3)).makeWritable())

        await env.sut.loadCodes()

        #expect(env.sut.codes.map(\.item.otpCode?.data.issuer) == ["Offered"])
    }

    /// AutoFill's search never checks killphrases: their keys aren't loaded in the extension (G2).
    @Test
    func search_neverFiresAKillphrase() async throws {
        let env = try await Environment.unlocked()
        var item = MacTestItems.code(issuer: "Example")
        item.metadata.killphrase = KillphraseDigester(key: .zero()).makeDigest(phrase: "kill me")
        _ = try await env.store.insert(item: item.makeWritable())

        env.sut.dataModel.itemsSearchQuery = "kill me"
        await env.sut.loadCodes()
        env.sut.dataModel.itemsSearchQuery = ""
        await env.sut.loadCodes()

        #expect(env.sut.codes.count == 1)
    }

    @MainActor
    private struct Environment {
        let vault: FakeAutofillVault
        let sut: VaultMacAutofillModel
        let store: VaultStoreSession

        init(mode: VaultAccessMode = .password, password: String? = "correct horse battery") throws {
            vault = FakeAutofillVault(password: password)
            let (dataModel, store) = try MacTestVault.make()
            self.store = store
            let settings = try AppLockSettingsStore(userDefaults: .nonPersistent())
            settings.isEnabled = true
            sut = VaultMacAutofillModel(
                dataModel: dataModel,
                vaultService: vault,
                accessMode: { mode },
                appLockSettings: settings,
                authentication: DeviceAuthenticationService(policy: DeviceAuthenticationPolicyAlwaysAllow()),
            )
        }

        static func unlocked() async throws -> Environment {
            let env = try Environment()
            await env.sut.prepareToUnlock()
            await env.sut.appLock.unlock()
            await env.sut.appLock.unlock(password: "correct horse battery")
            #expect(!env.sut.appLock.isLocked)
            return env
        }
    }
}

/// The App Lock Password, as the extension opens the vault with it, in memory.
@MainActor
final class FakeAutofillVault: VaultMacAutofillVaultUnlocking {
    private let base: FakeAppLockPasswordService
    var onNotEnoughMemory: (@MainActor () -> Void)?
    var hasHeadroom = true
    private(set) var lockCount = 0

    init(password: String?) {
        base = FakeAppLockPasswordService(password: password)
    }

    func hasMemoryHeadroomToUnlock() async throws -> Bool {
        hasHeadroom
    }

    var isPasswordSet: Bool {
        base.isPasswordSet
    }

    var erasesAfterFailedPasswords: Bool {
        base.erasesAfterFailedPasswords
    }

    var setAsideVaultCount: Int {
        base.setAsideVaultCount
    }

    func remainingDelay() async throws -> Duration {
        try await base.remainingDelay()
    }

    func unlock(password: String) async throws -> AppLockPasswordResult {
        try await base.unlock(password: password)
    }

    func setPassword(_ password: String, deletingSetAsideVaults: Bool) async throws {
        try await base.setPassword(password, deletingSetAsideVaults: deletingSetAsideVaults)
    }

    func changePassword(current: String, new: String) async throws -> AppLockPasswordResult {
        try await base.changePassword(current: current, new: new)
    }

    func turnOffPassword(current: String) async throws -> AppLockPasswordResult {
        try await base.turnOffPassword(current: current)
    }

    func makeDuressVault(current: String, password: String) async throws -> AppLockPasswordResult {
        try await base.makeDuressVault(current: current, password: password)
    }

    func setErasesAfterFailedPasswords(_ erases: Bool, current: String) async throws -> AppLockPasswordResult {
        try await base.setErasesAfterFailedPasswords(erases, current: current)
    }

    func openVaultWithoutPassword() async throws {
        try await base.openVaultWithoutPassword()
    }

    func lockVault() async {
        lockCount += 1
        await base.lockVault()
    }
}

@MainActor
struct VaultMacAutofillLockObserverTests {
    @Test(arguments: VaultMacLockTriggers.lockingDistributedNotifications)
    func distributedNotification_locks(name: Notification.Name) {
        let env = Environment()

        env.distributed.post(name: name, object: nil)

        #expect(env.events == [.macWillLock])
    }

    @Test(arguments: VaultMacLockTriggers.lockingWorkspaceNotifications)
    func workspaceNotification_locks(name: Notification.Name) {
        let env = Environment()

        env.workspace.post(name: name, object: nil)

        #expect(env.events == [.macWillLock])
    }

    @Test
    func anotherAppComingToTheFront_isTheUserLeaving() throws {
        let env = Environment()
        let other = try #require(NSWorkspace.shared.runningApplications.first { $0 != NSRunningApplication.current })

        env.workspace.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: other],
        )

        #expect(env.events == [.userDidLeave])
    }

    @Test
    func theHostComingToTheFront_isNotLeaving() {
        let env = Environment()

        env.workspace.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current],
        )

        #expect(env.events.isEmpty)
    }

    /// macOS shows the sheet's own Touch ID or password prompt from an agent of its own, which isn't the user leaving.
    @Test
    func anAgentComingToTheFront_whileItsOwnPromptIsUp_isNotLeaving() throws {
        let env = Environment()
        env.isAuthenticating = true

        try env.workspace.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: VaultMacLockTriggersTests.agent()],
        )

        #expect(env.events.isEmpty)
    }

    @Test
    func anotherAppComingToTheFront_whileItsOwnPromptIsUp_isTheUserLeaving() throws {
        let env = Environment()
        env.isAuthenticating = true

        try env.workspace.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: VaultMacLockTriggersTests.otherApp()],
        )

        #expect(env.events == [.userDidLeave])
    }

    @Test
    func stop_stopsObserving() {
        let env = Environment()

        env.sut.stop()
        env.distributed.post(name: VaultMacLockTriggers.lockingDistributedNotifications[0], object: nil)

        #expect(env.events.isEmpty)
    }

    private enum Event: Equatable {
        case macWillLock
        case userDidLeave
    }

    @MainActor
    private final class Environment {
        let distributed = NotificationCenter()
        let workspace = NotificationCenter()
        var events: [Event] = []
        var isAuthenticating = false
        private(set) var sut: VaultMacAutofillLockObserver!

        init() {
            sut = VaultMacAutofillLockObserver(
                hostProcess: NSRunningApplication.current.processIdentifier,
                isAuthenticating: { [weak self] in self?.isAuthenticating ?? false },
                distributedCenter: distributed,
                workspaceCenter: workspace,
                macWillLock: { [weak self] in self?.events.append(.macWillLock) },
                userDidLeave: { [weak self] in self?.events.append(.userDidLeave) },
            )
        }
    }
}
