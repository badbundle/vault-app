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

    /// An unlocked app lock with the App Lock Password set, and the triggers on centers of its own.
    @MainActor
    private struct Environment {
        let appLock: AppLockService
        let triggers: VaultMacLockTriggers
        let distributed = NotificationCenter()
        let workspace = NotificationCenter()
        let application = NotificationCenter()
        let sleeps = Sleeps()

        init(delay: AppLockDelay) async throws {
            let settings = try AppLockSettingsStore(userDefaults: .nonPersistent())
            settings.isEnabled = true
            settings.delay = delay
            appLock = AppLockService(
                settings: settings,
                authenticationService: DeviceAuthenticationService(policy: DeviceAuthenticationPolicyAlwaysAllow()),
                passwordService: FakeAppLockPasswordService(password: "password"),
                purgeSensitiveData: {},
            )
            await appLock.unlock()
            await appLock.unlock(password: "password")
            #expect(!appLock.isLocked)
            let sleeps = sleeps
            triggers = VaultMacLockTriggers(
                appLock: appLock,
                distributedCenter: distributed,
                workspaceCenter: workspace,
                applicationCenter: application,
                sleep: { try await sleeps.sleep(for: $0) },
            )
        }
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
