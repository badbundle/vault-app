import AppKit
import Foundation
import Synchronization
import TestHelpers
import Testing
import VaultFeed
@testable import VaultMac

@MainActor
struct VaultMacLockTriggersTests {
    @Test(arguments: VaultMacLockTriggers.lockingDistributedNotifications)
    func distributedNotification_locksAtOnceWhateverTheDelay(name: Notification.Name) async throws {
        let env = try await Environment(delay: .fifteenMinutes)

        env.distributed.post(name: name, object: nil)

        #expect(env.appLock.isLocked)
    }

    @Test(arguments: VaultMacLockTriggers.lockingWorkspaceNotifications)
    func workspaceNotification_locksAtOnceWhateverTheDelay(name: Notification.Name) async throws {
        let env = try await Environment(delay: .fifteenMinutes)

        env.workspace.post(name: name, object: nil)

        #expect(env.appLock.isLocked)
    }

    @Test
    func screenLocking_isHeardForTheScreenSaverAndTheLockScreen() {
        #expect(VaultMacLockTriggers.lockingDistributedNotifications.map(\.rawValue) == [
            "com.apple.screenIsLocked",
            "com.apple.screensaver.didstart",
        ])
        #expect(VaultMacLockTriggers.lockingWorkspaceNotifications == [
            NSWorkspace.willSleepNotification,
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification,
        ])
    }

    /// Even with Settings, Help or About still open, which keep Vault running.
    @Test
    func closingTheMainWindow_locksAtOnceWhateverTheDelay() async throws {
        let env = try await Environment(delay: .fifteenMinutes)
        let window = NSWindow()
        window.identifier = NSUserInterfaceItemIdentifier("main-AppWindow-1")

        env.application.post(name: NSWindow.willCloseNotification, object: window)

        #expect(env.appLock.isLocked)
    }

    @Test
    func closingAnotherWindow_leavesVaultUnlocked() async throws {
        let env = try await Environment(delay: .fifteenMinutes)
        let window = NSWindow()
        window.identifier = NSUserInterfaceItemIdentifier("help-AppWindow-1")

        env.application.post(name: NSWindow.willCloseNotification, object: window)

        #expect(!env.appLock.isLocked)
    }

    @Test
    func leavingTheApp_withRequireUnlockImmediately_locksAtOnce() async throws {
        let env = try await Environment(delay: .immediately)

        env.application.post(name: NSApplication.didResignActiveNotification, object: nil)

        #expect(env.appLock.isLocked)
    }

    @Test
    func leavingTheApp_withADelay_locksOnceItsPassedWhileStillAway() async throws {
        let env = try await Environment(delay: .oneMinute)

        env.application.post(name: NSApplication.didResignActiveNotification, object: nil)
        #expect(!env.appLock.isLocked)
        await env.sleeps.untilSleeping()
        #expect(env.sleeps.values == [.seconds(60)])
        env.sleeps.finish()
        await env.triggers.delayedLock?.value

        #expect(env.appLock.isLocked)
    }

    @Test
    func comingBackWithinTheDelay_staysUnlocked() async throws {
        let env = try await Environment(delay: .fiveMinutes)

        env.application.post(name: NSApplication.didResignActiveNotification, object: nil)
        let delayedLock = env.triggers.delayedLock
        await env.sleeps.untilSleeping()
        env.application.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        await delayedLock?.value

        #expect(!env.appLock.isLocked)
    }

    // MARK: - Vault's own prompt

    /// macOS shows Touch ID and the Mac's password from a process of its own, so Vault stops being the active app under
    /// its own prompt. Taking that for leaving locked Vault again, threw the answer away and asked again, forever.
    @Test(arguments: [AppLockDelay.immediately, .fiveMinutes])
    func unlocking_underItsOwnPrompt_isNotLeaving(delay: AppLockDelay) async throws {
        let env = try await Environment(delay: delay, unlocked: false)

        let unlocking = Task { await env.appLock.unlock() }
        await env.prompts.waitForPrompt()
        env.front.application = try Self.agent()
        env.application.post(name: NSApplication.didResignActiveNotification, object: nil)
        #expect(env.triggers.isBehindItsOwnPrompt)
        await env.prompts.answer(true)
        await unlocking.value
        env.application.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        // Time for a second prompt to come up, if coming back started unlocking again.
        try await Task.sleep(for: .milliseconds(100))

        guard case let .locked(locked) = env.appLock.state else {
            Issue.record("Expected Vault to be locked at its password")
            return
        }
        #expect(locked.step == .password)
        #expect(await env.prompts.promptCount == 1)
        await env.appLock.unlock(password: "password")
        #expect(!env.appLock.isLocked)
    }

    /// As for a locked item, a backup or a setting: with Require Unlock at Immediately, its prompt mustn't lock Vault.
    @Test
    func promptWhileUnlocked_withRequireUnlockImmediately_staysUnlocked() async throws {
        let env = try await Environment(delay: .immediately)

        let authenticating = Task { try await env.authentication.validateAuthentication(reason: "Test") }
        await env.prompts.waitForPrompt()
        env.front.application = try Self.agent()
        env.application.post(name: NSApplication.didResignActiveNotification, object: nil)
        #expect(!env.appLock.isLocked)
        await env.prompts.answer(true)
        try await authenticating.value
        env.application.post(name: NSApplication.didBecomeActiveNotification, object: nil)

        #expect(!env.appLock.isLocked)
        #expect(!env.triggers.isBehindItsOwnPrompt)
    }

    @Test
    func anotherAppComingToTheFront_whileItsOwnPromptIsUp_isLeaving() async throws {
        let env = try await Environment(delay: .immediately)

        let authenticating = Task { try? await env.authentication.validateAuthentication(reason: "Test") }
        await env.prompts.waitForPrompt()
        env.front.application = try Self.agent()
        env.application.post(name: NSApplication.didResignActiveNotification, object: nil)
        #expect(!env.appLock.isLocked)
        try env.workspace.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: Self.otherApp()],
        )

        #expect(env.appLock.isLocked)
        #expect(!env.triggers.isBehindItsOwnPrompt)
        await env.prompts.answer(false)
        await authenticating.value
    }

    @Test
    func leavingForAnotherApp_whileItsOwnPromptIsUp_isLeaving() async throws {
        let env = try await Environment(delay: .immediately)

        let authenticating = Task { try? await env.authentication.validateAuthentication(reason: "Test") }
        await env.prompts.waitForPrompt()
        env.front.application = try Self.otherApp()
        env.application.post(name: NSApplication.didResignActiveNotification, object: nil)

        #expect(env.appLock.isLocked)
        await env.prompts.answer(false)
        await authenticating.value
    }

    @Test
    func workspaceActivation_withoutItsOwnPromptUp_doesNothing() async throws {
        let env = try await Environment(delay: .immediately)

        try env.workspace.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: Self.otherApp()],
        )

        #expect(!env.appLock.isLocked)
    }

    @Test
    func isAnotherApp_isOnlyAnOrdinaryAppOtherThanVault() throws {
        #expect(try VaultMacLockTriggers.isAnotherApp(Self.otherApp()))
        #expect(try !VaultMacLockTriggers.isAnotherApp(Self.agent()))
        #expect(!VaultMacLockTriggers.isAnotherApp(.current))
        #expect(!VaultMacLockTriggers.isAnotherApp(nil))
    }

    /// An ordinary app other than this one, such as the Finder.
    static func otherApp() throws -> NSRunningApplication {
        try #require(NSWorkspace.shared.runningApplications.first {
            $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        })
    }

    /// An agent with no Dock icon, as the one that shows Touch ID and the Mac's password is.
    static func agent() throws -> NSRunningApplication {
        try #require(NSWorkspace.shared.runningApplications.first { $0.activationPolicy == .accessory })
    }

    /// An app lock with the App Lock Password set, unlocked unless asked, its device authentication's prompts up until
    /// the test answers them, and the triggers on centers of their own.
    @MainActor
    private struct Environment {
        let appLock: AppLockService
        let authentication: DeviceAuthenticationService
        let prompts = PendingAuthenticationPolicy()
        let triggers: VaultMacLockTriggers
        let distributed = NotificationCenter()
        let workspace = NotificationCenter()
        let application = NotificationCenter()
        let front = Front()
        let sleeps = Sleeps()

        /// The app in front, as Vault stops being the active app.
        final class Front {
            var application: NSRunningApplication?
        }

        init(delay: AppLockDelay, unlocked: Bool = true) async throws {
            let settings = try AppLockSettingsStore(userDefaults: .nonPersistent())
            settings.isEnabled = true
            settings.delay = delay
            authentication = DeviceAuthenticationService(policy: prompts)
            appLock = AppLockService(
                settings: settings,
                authenticationService: authentication,
                passwordService: FakeAppLockPasswordService(password: "password"),
                purgeSensitiveData: {},
            )
            if unlocked {
                let unlocking = Task { [appLock] in await appLock.unlock() }
                await prompts.waitForPrompt()
                await prompts.answer(true)
                await unlocking.value
                await appLock.unlock(password: "password")
                #expect(!appLock.isLocked)
            }
            let sleeps = sleeps
            let front = front
            triggers = VaultMacLockTriggers(
                appLock: appLock,
                authentication: authentication,
                distributedCenter: distributed,
                workspaceCenter: workspace,
                applicationCenter: application,
                frontApplication: { front.application },
                sleep: { try await sleeps.sleep(for: $0) },
            )
        }
    }
}

/// A device authentication whose prompts stay up until the test answers them.
private actor PendingAuthenticationPolicy: DeviceAuthenticationPolicy {
    nonisolated var canAuthenicateWithPasscode: Bool {
        true
    }

    nonisolated var canAuthenticateWithBiometrics: Bool {
        true
    }

    private var pending = [CheckedContinuation<Bool, any Error>]()
    private(set) var promptCount = 0

    func authenticateWithBiometrics(reason _: String) async throws -> Bool {
        try await prompt()
    }

    func authenticateWithPasscode(reason _: String) async throws -> Bool {
        try await prompt()
    }

    private func prompt() async throws -> Bool {
        promptCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            pending.append(continuation)
        }
    }

    /// Waits (for up to 5 seconds) until a prompt is up.
    func waitForPrompt() async {
        let deadline = ContinuousClock.now + .seconds(5)
        while pending.isEmpty, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    func answer(_ authenticated: Bool) {
        guard !pending.isEmpty else {
            Issue.record("No prompt is up to answer")
            return
        }
        pending.removeFirst().resume(returning: authenticated)
    }
}

/// Waits that end only when a test says, or when they're cancelled, and the durations they were asked to wait.
private final class Sleeps: Sendable {
    private struct State {
        var values = [Duration]()
        var waiting = [UUID: CheckedContinuation<Void, Never>]()
        var cancelled = Set<UUID>()
    }

    private let state = Mutex(State())

    var values: [Duration] {
        state.withLock(\.values)
    }

    func sleep(for duration: Duration) async throws {
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let isCancelled = state.withLock { state in
                    state.values.append(duration)
                    guard !state.cancelled.contains(id) else { return true }
                    state.waiting[id] = continuation
                    return false
                }
                if isCancelled {
                    continuation.resume()
                }
            }
        } onCancel: {
            let continuation = state.withLock { state in
                state.cancelled.insert(id)
                return state.waiting.removeValue(forKey: id)
            }
            continuation?.resume()
        }
        try Task.checkCancellation()
    }

    /// Waits until something is waiting.
    func untilSleeping() async {
        while state.withLock(\.waiting).isEmpty {
            await Task.yield()
        }
    }

    /// Ends every wait.
    func finish() {
        let continuations = state.withLock { state in
            defer { state.waiting.removeAll() }
            return Array(state.waiting.values)
        }
        for continuation in continuations {
            continuation.resume()
        }
    }
}
