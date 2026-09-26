import Foundation
import LocalAuthentication
import TestHelpers
import Testing
@testable import VaultFeed

@MainActor
struct AppLockServiceTests {
    // MARK: - Launch

    @Test
    func init_lockOff_isUnlocked() throws {
        let (sut, _) = try makeSUT(isEnabled: false)

        #expect(!sut.isEnabled)
        #expect(sut.state == .unlocked)
    }

    @Test
    func init_lockOn_startsLocked() throws {
        let (sut, _) = try makeSUT(isEnabled: true)

        #expect(sut.isEnabled)
        #expect(sut.state == .locked(.init(step: .deviceAuthentication)))
    }

    @Test
    func init_lockOn_doesNotPromptBeforeTheAppIsActive() throws {
        let policy = countingPolicy(result: true)
        let (sut, _) = try makeSUT(isEnabled: true, policy: policy)

        sut.scenePhaseDidChange(to: .inactive)

        #expect(sut.automaticUnlock == nil)
        #expect(policy.authenticateWithBiometricsCallCount == 0)
    }

    @Test
    func launchActive_lockOn_promptsAndUnlocks() async throws {
        let policy = countingPolicy(result: true)
        let (sut, _) = try makeSUT(isEnabled: true, policy: policy)

        await activate(sut)

        #expect(sut.state == .unlocked)
        #expect(policy.authenticateWithBiometricsCallCount == 1)
    }

    @Test
    func launchActive_lockOff_neverPrompts() async throws {
        let policy = countingPolicy(result: true)
        let (sut, _) = try makeSUT(isEnabled: false, policy: policy)

        await activate(sut)

        #expect(sut.state == .unlocked)
        #expect(policy.authenticateWithBiometricsCallCount == 0)
    }

    // MARK: - Authentication outcomes

    @Test
    func unlock_authenticationFails_staysLockedAndSaysSo() async throws {
        let (sut, _) = try makeSUT(isEnabled: true, policy: countingPolicy(result: false))

        await activate(sut)

        #expect(sut.state == .locked(.init(step: .deviceAuthentication, failure: .failed)))
    }

    @Test
    func unlock_authenticationCancelled_staysLocked() async throws {
        let (sut, _) = try makeSUT(isEnabled: true, policy: throwingPolicy(LAError(.userCancel)))

        await activate(sut)

        #expect(sut.state == .locked(.init(step: .deviceAuthentication, failure: .cancelled)))
    }

    @Test
    func unlock_authenticationCancelledBySystem_staysLocked() async throws {
        let (sut, _) = try makeSUT(isEnabled: true, policy: throwingPolicy(LAError(.systemCancel)))

        await activate(sut)

        #expect(sut.state == .locked(.init(step: .deviceAuthentication, failure: .cancelled)))
    }

    @Test
    func unlock_otherAuthenticationError_staysLockedAndFails() async throws {
        let (sut, _) = try makeSUT(isEnabled: true, policy: throwingPolicy(TestError()))

        await activate(sut)

        #expect(sut.state == .locked(.init(step: .deviceAuthentication, failure: .failed)))
    }

    @Test
    func unlock_deviceHasNoPasscode_staysLocked() async throws {
        // Removing the passcode doesn't open the vault: the lock waits for one to be set up again.
        let (sut, _) = try makeSUT(isEnabled: true, policy: DeviceAuthenticationPolicyCannotAuthenticate())

        await activate(sut)

        #expect(sut.state == .locked(.init(step: .deviceAuthentication, failure: .unavailable)))
    }

    @Test
    func unlock_retryAfterFailure_unlocks() async throws {
        let policy = DeviceAuthenticationPolicyMock(
            canAuthenicateWithPasscode: true,
            canAuthenticateWithBiometrics: true,
        )
        policy.authenticateWithBiometricsHandler = { _ in
            // Fails the first time only.
            policy.authenticateWithBiometricsCallCount > 1
        }
        let (sut, _) = try makeSUT(isEnabled: true, policy: policy)
        await activate(sut)
        #expect(sut.state == .locked(.init(step: .deviceAuthentication, failure: .failed)))

        await sut.unlock()

        #expect(sut.state == .unlocked)
    }

    @Test
    func unlock_showsTheStepInProgressWhileThePromptIsUp() async throws {
        let policy = PendingAuthenticationPolicy()
        let (sut, _) = try makeSUT(isEnabled: true, policy: policy)

        sut.scenePhaseDidChange(to: .active)
        await policy.waitForPrompt()

        #expect(sut.state == .locked(.init(step: .deviceAuthentication, isInProgress: true)))

        await policy.answer(true)
        await sut.automaticUnlock?.value

        #expect(sut.state == .unlocked)
    }

    @Test
    func unlock_whileAlreadyInProgress_doesNotPromptTwice() async throws {
        let policy = PendingAuthenticationPolicy()
        let (sut, _) = try makeSUT(isEnabled: true, policy: policy)
        sut.scenePhaseDidChange(to: .active)
        await policy.waitForPrompt()

        await sut.unlock()

        #expect(await policy.promptCount == 1)
        await policy.answer(true)
        await sut.automaticUnlock?.value
    }

    @Test
    func unlock_whenUnlocked_doesNothing() async throws {
        let policy = countingPolicy(result: true)
        let (sut, _) = try makeSUT(isEnabled: false, policy: policy)

        await sut.unlock()

        #expect(sut.state == .unlocked)
        #expect(policy.authenticateWithBiometricsCallCount == 0)
    }

    // MARK: - Automatic prompts

    @Test
    func active_afterCancelling_doesNotPromptAgainUntilTheAppHasBeenInTheBackground() async throws {
        let policy = DeviceAuthenticationPolicyMock(
            canAuthenicateWithPasscode: true,
            canAuthenticateWithBiometrics: true,
        )
        policy.authenticateWithBiometricsHandler = { _ in
            throw LAError(.userCancel)
        }
        let (sut, _) = try makeSUT(isEnabled: true, policy: policy)
        await activate(sut)
        #expect(policy.authenticateWithBiometricsCallCount == 1)

        // The prompt itself makes the app inactive, and Control Center does too: neither prompts again.
        sut.scenePhaseDidChange(to: .inactive)
        await activate(sut)
        #expect(policy.authenticateWithBiometricsCallCount == 1)

        sut.scenePhaseDidChange(to: .background)
        sut.scenePhaseDidChange(to: .inactive)
        await activate(sut)
        #expect(policy.authenticateWithBiometricsCallCount == 2)
    }

    // MARK: - Background and inactive

    @Test
    func background_lockOn_locksAndPurgesSensitiveData() async throws {
        let purge = CallCounter()
        let (sut, _) = try makeSUT(isEnabled: true, policy: countingPolicy(result: true), purge: purge)
        await activate(sut)
        #expect(sut.state == .unlocked)
        #expect(purge.callCount == 0)

        sut.scenePhaseDidChange(to: .inactive)
        sut.scenePhaseDidChange(to: .background)

        #expect(sut.state == .locked(.init(step: .deviceAuthentication)))
        #expect(purge.callCount == 1)
    }

    @Test
    func background_lockOff_staysUnlockedAndPurgesNothing() throws {
        let purge = CallCounter()
        let (sut, _) = try makeSUT(isEnabled: false, purge: purge)

        sut.scenePhaseDidChange(to: .inactive)
        sut.scenePhaseDidChange(to: .background)

        #expect(sut.state == .unlocked)
        #expect(purge.callCount == 0)
    }

    @Test
    func background_afterAFailedUnlock_clearsTheFailure() async throws {
        let (sut, _) = try makeSUT(isEnabled: true, policy: countingPolicy(result: false))
        await activate(sut)

        sut.scenePhaseDidChange(to: .background)

        #expect(sut.state == .locked(.init(step: .deviceAuthentication)))
    }

    @Test
    func inactive_lockOn_doesNotLock() async throws {
        let purge = CallCounter()
        let (sut, _) = try makeSUT(isEnabled: true, policy: countingPolicy(result: true), purge: purge)
        await activate(sut)

        sut.scenePhaseDidChange(to: .inactive)

        #expect(sut.state == .unlocked)
        #expect(purge.callCount == 0)
    }

    @Test
    func foreground_afterBackground_promptsAndUnlocks() async throws {
        let policy = countingPolicy(result: true)
        let (sut, _) = try makeSUT(isEnabled: true, policy: policy)
        await activate(sut)
        sut.scenePhaseDidChange(to: .background)

        sut.scenePhaseDidChange(to: .inactive)
        await activate(sut)

        #expect(sut.state == .unlocked)
        #expect(policy.authenticateWithBiometricsCallCount == 2)
    }

    @Test
    func background_whilePrompting_discardsTheStaleResult() async throws {
        // Face ID succeeding after the app has already gone to the background (and so locked again) must not
        // unlock that new lock.
        let policy = PendingAuthenticationPolicy()
        let (sut, _) = try makeSUT(isEnabled: true, policy: policy)
        sut.scenePhaseDidChange(to: .active)
        await policy.waitForPrompt()

        sut.scenePhaseDidChange(to: .background)
        await policy.answer(true)
        await sut.automaticUnlock?.value

        #expect(sut.state == .locked(.init(step: .deviceAuthentication)))
    }

    @Test
    func background_whilePrompting_promptsAfreshOnceTheStaleResultIsInIfActive() async throws {
        let policy = PendingAuthenticationPolicy()
        let (sut, _) = try makeSUT(isEnabled: true, policy: policy)
        sut.scenePhaseDidChange(to: .active)
        await policy.waitForPrompt()
        let staleUnlock = sut.automaticUnlock

        // Back before the system has finished cancelling the first prompt: the step stays underway, so there's
        // no second prompt yet.
        sut.scenePhaseDidChange(to: .background)
        sut.scenePhaseDidChange(to: .active)
        #expect(sut.state == .locked(.init(step: .deviceAuthentication, isInProgress: true)))
        #expect(await policy.promptCount == 1)

        await policy.answer(throwing: LAError(.systemCancel))
        await staleUnlock?.value
        await policy.waitForPrompt(count: 2)
        await policy.answer(true)
        await sut.automaticUnlock?.value

        #expect(sut.state == .unlocked)
    }

    // MARK: - Privacy cover

    @Test
    func requiresPrivacyCover_lockOn_whenNotActive() throws {
        let (sut, _) = try makeSUT(isEnabled: true)

        #expect(!sut.requiresPrivacyCover(in: .active))
        #expect(sut.requiresPrivacyCover(in: .inactive))
        #expect(sut.requiresPrivacyCover(in: .background))
    }

    @Test
    func requiresPrivacyCover_lockOff_never() throws {
        let (sut, _) = try makeSUT(isEnabled: false)

        #expect(!sut.requiresPrivacyCover(in: .active))
        #expect(!sut.requiresPrivacyCover(in: .inactive))
        #expect(!sut.requiresPrivacyCover(in: .background))
    }

    @Test
    func requiresPrivacyCover_notWhileTheAppsOwnPromptIsUp() async throws {
        // The app is inactive under its own Face ID prompts: the cover stays away rather than flashing up behind
        // them, unless the app goes to the background.
        let policy = PendingAuthenticationPolicy()
        let authenticationService = DeviceAuthenticationService(policy: policy)
        let (sut, _) = try makeSUT(isEnabled: true, authenticationService: authenticationService)

        let prompt = Task { try await authenticationService.authenticate(reason: "Unlock item") }
        await policy.waitForPrompt()

        #expect(!sut.requiresPrivacyCover(in: .inactive))
        #expect(sut.requiresPrivacyCover(in: .background))

        await policy.answer(true)
        _ = try await prompt.value
        #expect(sut.requiresPrivacyCover(in: .inactive))
    }

    // MARK: - Waiting for unlock

    @Test
    func performWhenUnlocked_runsAtOnceWhenUnlocked() throws {
        let (sut, _) = try makeSUT(isEnabled: false)
        let action = CallCounter()

        sut.performWhenUnlocked { action.increment() }

        #expect(action.callCount == 1)
    }

    @Test
    func performWhenUnlocked_waitsForTheUserToUnlock() async throws {
        let policy = DeviceAuthenticationPolicyMock(
            canAuthenicateWithPasscode: true,
            canAuthenticateWithBiometrics: true,
        )
        policy.authenticateWithBiometricsHandler = { _ in
            policy.authenticateWithBiometricsCallCount > 1
        }
        let (sut, _) = try makeSUT(isEnabled: true, policy: policy)
        let action = CallCounter()

        sut.performWhenUnlocked { action.increment() }
        #expect(action.callCount == 0)

        await activate(sut)
        // A failed unlock doesn't run it.
        #expect(action.callCount == 0)

        await sut.unlock()
        #expect(action.callCount == 1)

        // Nor does the next unlock run it again.
        sut.scenePhaseDidChange(to: .background)
        await activate(sut)
        #expect(sut.state == .unlocked)
        #expect(action.callCount == 1)
    }

    @Test
    func performWhenUnlocked_runsWaitingActionsInOrder() async throws {
        let (sut, _) = try makeSUT(isEnabled: true, policy: countingPolicy(result: true))
        var order = [Int]()

        sut.performWhenUnlocked { order.append(1) }
        sut.performWhenUnlocked { order.append(2) }
        await activate(sut)

        #expect(order == [1, 2])
    }

    // MARK: - Settings

    @Test
    func setEnabled_on_authenticatesThenTurnsOnAndSaves() async throws {
        let policy = countingPolicy(result: true)
        let didChange = CallCounter()
        let (sut, settings) = try makeSUT(isEnabled: false, policy: policy, didChangeSettings: didChange)

        await sut.setEnabled(true)

        #expect(sut.isEnabled)
        #expect(settings.isEnabled)
        #expect(policy.authenticateWithBiometricsCallCount == 1)
        #expect(didChange.callCount == 1)
        // The user's here, having just authenticated: the app locks next time it goes to the background.
        #expect(sut.state == .unlocked)
    }

    @Test
    func setEnabled_on_authenticationFails_staysOff() async throws {
        let didChange = CallCounter()
        let (sut, settings) = try makeSUT(
            isEnabled: false,
            policy: countingPolicy(result: false),
            didChangeSettings: didChange,
        )

        await sut.setEnabled(true)

        #expect(!sut.isEnabled)
        #expect(!settings.isEnabled)
        #expect(didChange.callCount == 0)
    }

    @Test
    func setEnabled_on_withoutAPasscode_isNotPossible() async throws {
        let (sut, settings) = try makeSUT(isEnabled: false, policy: DeviceAuthenticationPolicyCannotAuthenticate())

        #expect(!sut.canEnable)
        await sut.setEnabled(true)

        #expect(!sut.isEnabled)
        #expect(!settings.isEnabled)
    }

    @Test
    func canEnable_withAPasscode_orWhenAlreadyOn() throws {
        let (withPasscode, _) = try makeSUT(isEnabled: false, policy: DeviceAuthenticationPolicyAlwaysAllow())
        let (alreadyOn, _) = try makeSUT(isEnabled: true, policy: DeviceAuthenticationPolicyCannotAuthenticate())

        #expect(withPasscode.canEnable)
        #expect(alreadyOn.canEnable)
    }

    @Test
    func setEnabled_off_authenticatesThenTurnsOffAndSaves() async throws {
        let policy = countingPolicy(result: true)
        let didChange = CallCounter()
        let (sut, settings) = try makeSUT(isEnabled: true, policy: policy, didChangeSettings: didChange)
        await activate(sut)

        await sut.setEnabled(false)

        #expect(!sut.isEnabled)
        #expect(!settings.isEnabled)
        #expect(policy.authenticateWithBiometricsCallCount == 2)
        #expect(didChange.callCount == 1)

        sut.scenePhaseDidChange(to: .background)
        #expect(sut.state == .unlocked)
    }

    @Test
    func setEnabled_off_authenticationFails_staysOn() async throws {
        let policy = DeviceAuthenticationPolicyMock(
            canAuthenicateWithPasscode: true,
            canAuthenticateWithBiometrics: true,
        )
        policy.authenticateWithBiometricsHandler = { _ in
            // Unlocks the app, then fails to turn the lock off.
            policy.authenticateWithBiometricsCallCount == 1
        }
        let (sut, settings) = try makeSUT(isEnabled: true, policy: policy)
        await activate(sut)

        await sut.setEnabled(false)

        #expect(sut.isEnabled)
        #expect(settings.isEnabled)
    }

    @Test
    func setEnabled_off_authenticationCancelled_staysOn() async throws {
        let policy = DeviceAuthenticationPolicyMock(
            canAuthenicateWithPasscode: true,
            canAuthenticateWithBiometrics: true,
        )
        policy.authenticateWithBiometricsHandler = { _ in
            if policy.authenticateWithBiometricsCallCount == 1 {
                return true
            }
            throw LAError(.userCancel)
        }
        let (sut, settings) = try makeSUT(isEnabled: true, policy: policy)
        await activate(sut)

        await sut.setEnabled(false)

        #expect(sut.isEnabled)
        #expect(settings.isEnabled)
    }

    @Test
    func setEnabled_whileLocked_doesNothing() async throws {
        let policy = countingPolicy(result: true)
        let (sut, settings) = try makeSUT(isEnabled: true, policy: policy)

        await sut.setEnabled(false)

        #expect(sut.isEnabled)
        #expect(settings.isEnabled)
        #expect(policy.authenticateWithBiometricsCallCount == 0)
    }

    @Test
    func setEnabled_off_appLocksWhileThePromptIsUp_staysOn() async throws {
        let policy = PendingAuthenticationPolicy()
        let (sut, settings) = try makeSUT(isEnabled: true, policy: policy)
        sut.scenePhaseDidChange(to: .active)
        await policy.waitForPrompt()
        await policy.answer(true)
        await sut.automaticUnlock?.value
        #expect(sut.state == .unlocked)

        let turningOff = Task { await sut.setEnabled(false) }
        await policy.waitForPrompt(count: 2)
        #expect(sut.isChangingSettings)
        sut.scenePhaseDidChange(to: .background)
        await policy.answer(true)
        await turningOff.value

        #expect(sut.isEnabled)
        #expect(settings.isEnabled)
        #expect(!sut.isChangingSettings)
        #expect(sut.isLocked)
    }

    // MARK: - Delay

    @Test
    func init_readsTheDelay() throws {
        let (sut, _) = try makeSUT(isEnabled: true, delay: .fiveMinutes)

        #expect(sut.delay == .fiveMinutes)
    }

    @Test(arguments: [AppLockDelay.oneMinute, .fiveMinutes, .fifteenMinutes])
    func delay_backSooner_staysUnlocked(delay: AppLockDelay) async throws {
        let clock = FakeAppLockClock()
        let purge = CallCounter()
        let (sut, _) = try makeSUT(isEnabled: true, delay: delay, clock: clock, purge: purge)
        await activate(sut)

        leaveForeground(sut)
        clock.advance(by: delay.duration - .seconds(1))
        returnToForeground(sut)

        #expect(sut.state == .unlocked)
        #expect(purge.callCount == 0)
    }

    @Test(arguments: [AppLockDelay.oneMinute, .fiveMinutes, .fifteenMinutes])
    func delay_backOnceItsUp_locks(delay: AppLockDelay) async throws {
        let clock = FakeAppLockClock()
        let purge = CallCounter()
        let (sut, _) = try makeSUT(isEnabled: true, delay: delay, clock: clock, purge: purge)
        await activate(sut)

        leaveForeground(sut)
        clock.advance(by: delay.duration)
        returnToForeground(sut)

        #expect(sut.isLocked)
        #expect(purge.callCount == 1)
    }

    @Test
    func delay_backMuchLater_locksAndPrompts() async throws {
        let clock = FakeAppLockClock()
        let policy = countingPolicy(result: true)
        let (sut, _) = try makeSUT(isEnabled: true, delay: .oneMinute, policy: policy, clock: clock)
        await activate(sut)

        leaveForeground(sut)
        clock.advance(by: .seconds(60 * 60 * 24))
        sut.scenePhaseDidChange(to: .inactive)
        #expect(sut.state == .locked(.init(step: .deviceAuthentication)))
        await activate(sut)

        #expect(sut.state == .unlocked)
        #expect(policy.authenticateWithBiometricsCallCount == 2)
    }

    @Test
    func delay_locksAsSoonAsTheAppIsBack_beforeItsActive() async throws {
        // The first thing on the way back is going inactive: locking then means the vault is never shown.
        let clock = FakeAppLockClock()
        let (sut, _) = try makeSUT(isEnabled: true, delay: .oneMinute, clock: clock)
        await activate(sut)
        leaveForeground(sut)
        clock.advance(by: .seconds(61))

        sut.scenePhaseDidChange(to: .inactive)

        #expect(sut.isLocked)
    }

    @Test
    func delay_backStraightToActive_stillLocks() async throws {
        let clock = FakeAppLockClock()
        let (sut, _) = try makeSUT(isEnabled: true, delay: .oneMinute, clock: clock)
        await activate(sut)
        leaveForeground(sut)
        clock.advance(by: .seconds(61))

        sut.scenePhaseDidChange(to: .active)

        #expect(sut.isLocked)
        await sut.automaticUnlock?.value
    }

    @Test
    func delay_countsFromTheFirstReportOfTheBackground() async throws {
        // The app hears about going to the background from UIKit and from SwiftUI. The second mustn't restart it.
        let clock = FakeAppLockClock()
        let (sut, _) = try makeSUT(isEnabled: true, delay: .oneMinute, clock: clock)
        await activate(sut)

        leaveForeground(sut)
        clock.advance(by: .seconds(50))
        sut.scenePhaseDidChange(to: .background)
        clock.advance(by: .seconds(10))
        returnToForeground(sut)

        #expect(sut.isLocked)
    }

    @Test
    func delay_startsAgainOnEachTripToTheBackground() async throws {
        let clock = FakeAppLockClock()
        let (sut, _) = try makeSUT(isEnabled: true, delay: .oneMinute, clock: clock)
        await activate(sut)

        leaveForeground(sut)
        clock.advance(by: .seconds(50))
        returnToForeground(sut)
        leaveForeground(sut)
        clock.advance(by: .seconds(50))
        returnToForeground(sut)

        #expect(sut.state == .unlocked)
    }

    @Test
    func delay_timeInTheForegroundDoesNotCount() async throws {
        let clock = FakeAppLockClock()
        let (sut, _) = try makeSUT(isEnabled: true, delay: .oneMinute, clock: clock)
        await activate(sut)

        clock.advance(by: .seconds(60 * 60))
        leaveForeground(sut)
        returnToForeground(sut)

        #expect(sut.state == .unlocked)
    }

    @Test
    func delay_clockGoingBackwards_locks() async throws {
        // Changing the device's date and time doesn't move this clock at all. If time ever ran backwards anyway,
        // it's no reason to stay unlocked.
        let clock = FakeAppLockClock()
        let (sut, _) = try makeSUT(isEnabled: true, delay: .fifteenMinutes, clock: clock)
        await activate(sut)

        leaveForeground(sut)
        clock.advance(by: .seconds(-60 * 60))
        returnToForeground(sut)

        #expect(sut.isLocked)
    }

    @Test
    func delay_restart_alwaysStartsLocked() async throws {
        // Restarting the device (or iOS ending the app in the background) means a new launch: it starts locked,
        // however recently the app was used and whatever the delay.
        let clock = FakeAppLockClock()
        let (sut, settings) = try makeSUT(isEnabled: true, delay: .fifteenMinutes, clock: clock)
        await activate(sut)
        leaveForeground(sut)

        let relaunched = AppLockService(
            settings: settings,
            authenticationService: DeviceAuthenticationService(policy: .alwaysAllow),
            clock: clock,
            purgeSensitiveData: {},
        )

        #expect(relaunched.isLocked)
    }

    @Test
    func delay_privacyCoverStillShowsAtOnce() throws {
        let (sut, _) = try makeSUT(isEnabled: true, delay: .fifteenMinutes)

        #expect(sut.requiresPrivacyCover(in: .inactive))
        #expect(sut.requiresPrivacyCover(in: .background))
    }

    @Test
    func delay_backgroundWhileLocked_stillRearmsThePrompt() async throws {
        let clock = FakeAppLockClock()
        let policy = DeviceAuthenticationPolicyMock(
            canAuthenicateWithPasscode: true,
            canAuthenticateWithBiometrics: true,
        )
        policy.authenticateWithBiometricsHandler = { _ in throw LAError(.userCancel) }
        let (sut, _) = try makeSUT(isEnabled: true, delay: .fifteenMinutes, policy: policy, clock: clock)
        await activate(sut)
        #expect(policy.authenticateWithBiometricsCallCount == 1)

        leaveForeground(sut)
        returnToForeground(sut)
        await sut.automaticUnlock?.value

        #expect(policy.authenticateWithBiometricsCallCount == 2)
    }

    // MARK: - Changing the delay

    @Test
    func setDelay_longer_authenticatesThenSaves() async throws {
        let policy = countingPolicy(result: true)
        let (sut, settings) = try makeSUT(isEnabled: false, delay: .immediately, policy: policy)
        await sut.setEnabled(true)

        await sut.setDelay(.fiveMinutes)

        #expect(sut.delay == .fiveMinutes)
        #expect(settings.delay == .fiveMinutes)
        #expect(policy.authenticateWithBiometricsCallCount == 2)
    }

    @Test
    func setDelay_longer_authenticationFails_staysTheSame() async throws {
        let policy = DeviceAuthenticationPolicyMock(
            canAuthenicateWithPasscode: true,
            canAuthenticateWithBiometrics: true,
        )
        policy.authenticateWithBiometricsHandler = { _ in
            // Turns the lock on, then fails to lengthen the delay.
            policy.authenticateWithBiometricsCallCount == 1
        }
        let (sut, settings) = try makeSUT(isEnabled: false, policy: policy)
        await sut.setEnabled(true)

        await sut.setDelay(.fifteenMinutes)

        #expect(sut.delay == .immediately)
        #expect(settings.delay == .immediately)
    }

    @Test
    func setDelay_longer_authenticationCancelled_staysTheSame() async throws {
        let policy = DeviceAuthenticationPolicyMock(
            canAuthenicateWithPasscode: true,
            canAuthenticateWithBiometrics: true,
        )
        policy.authenticateWithBiometricsHandler = { _ in
            if policy.authenticateWithBiometricsCallCount == 1 {
                return true
            }
            throw LAError(.userCancel)
        }
        let (sut, settings) = try makeSUT(isEnabled: false, policy: policy)
        await sut.setEnabled(true)

        await sut.setDelay(.oneMinute)

        #expect(sut.delay == .immediately)
        #expect(settings.delay == .immediately)
    }

    @Test
    func setDelay_shorter_savesWithoutAuthenticating() async throws {
        let policy = countingPolicy(result: true)
        let (sut, settings) = try makeSUT(isEnabled: true, delay: .fifteenMinutes, policy: policy)
        await activate(sut)
        #expect(policy.authenticateWithBiometricsCallCount == 1)

        await sut.setDelay(.oneMinute)
        await sut.setDelay(.immediately)

        #expect(sut.delay == .immediately)
        #expect(settings.delay == .immediately)
        #expect(policy.authenticateWithBiometricsCallCount == 1)
    }

    @Test
    func setDelay_takesEffectOnTheNextTripToTheBackground() async throws {
        let clock = FakeAppLockClock()
        let (sut, _) = try makeSUT(isEnabled: false, clock: clock)
        await sut.setEnabled(true)
        await sut.setDelay(.fiveMinutes)

        leaveForeground(sut)
        clock.advance(by: .seconds(60))
        returnToForeground(sut)

        #expect(sut.state == .unlocked)
    }

    @Test
    func setDelay_lockOff_doesNothing() async throws {
        let policy = countingPolicy(result: true)
        let (sut, settings) = try makeSUT(isEnabled: false, policy: policy)

        await sut.setDelay(.fiveMinutes)

        #expect(sut.delay == .immediately)
        #expect(settings.delay == .immediately)
        #expect(policy.authenticateWithBiometricsCallCount == 0)
    }

    @Test
    func setDelay_whileLocked_doesNothing() async throws {
        let policy = countingPolicy(result: true)
        let (sut, settings) = try makeSUT(isEnabled: true, policy: policy)

        await sut.setDelay(.fiveMinutes)

        #expect(sut.delay == .immediately)
        #expect(settings.delay == .immediately)
        #expect(policy.authenticateWithBiometricsCallCount == 0)
    }

    @Test
    func setEnabled_off_withADelay_neverLocks() async throws {
        let clock = FakeAppLockClock()
        let (sut, _) = try makeSUT(isEnabled: true, delay: .oneMinute, clock: clock)
        await activate(sut)
        leaveForeground(sut)
        returnToForeground(sut)

        await sut.setEnabled(false)
        leaveForeground(sut)
        clock.advance(by: .seconds(60 * 60))
        returnToForeground(sut)

        #expect(sut.state == .unlocked)
    }
}

// MARK: - Helpers

extension AppLockServiceTests {
    private func makeSUT(
        isEnabled: Bool,
        delay: AppLockDelay = .immediately,
        policy: any DeviceAuthenticationPolicy = DeviceAuthenticationPolicyAlwaysAllow(),
        authenticationService: DeviceAuthenticationService? = nil,
        clock: FakeAppLockClock = FakeAppLockClock(),
        purge: CallCounter = CallCounter(),
        didChangeSettings: CallCounter = CallCounter(),
    ) throws -> (AppLockService, AppLockSettingsStore) {
        let settings = try AppLockSettingsStore(userDefaults: .nonPersistent())
        settings.isEnabled = isEnabled
        settings.delay = delay
        let sut = AppLockService(
            settings: settings,
            authenticationService: authenticationService ?? DeviceAuthenticationService(policy: policy),
            clock: clock,
            purgeSensitiveData: { purge.increment() },
            didChangeSettings: { didChangeSettings.increment() },
        )
        return (sut, settings)
    }

    /// Active to background, as the system reports it.
    private func leaveForeground(_ sut: AppLockService) {
        sut.scenePhaseDidChange(to: .inactive)
        sut.scenePhaseDidChange(to: .background)
    }

    /// Background to active, without waiting for a prompt that starts.
    private func returnToForeground(_ sut: AppLockService) {
        sut.scenePhaseDidChange(to: .inactive)
        sut.scenePhaseDidChange(to: .active)
    }

    /// Brings the app to the foreground and waits for any prompt that starts.
    private func activate(_ sut: AppLockService) async {
        sut.scenePhaseDidChange(to: .active)
        await sut.automaticUnlock?.value
    }

    private func countingPolicy(result: Bool) -> DeviceAuthenticationPolicyMock {
        let policy = DeviceAuthenticationPolicyMock(
            canAuthenicateWithPasscode: true,
            canAuthenticateWithBiometrics: true,
        )
        policy.authenticateWithBiometricsHandler = { _ in result }
        return policy
    }

    private func throwingPolicy(_ error: any Error & Sendable) -> DeviceAuthenticationPolicyMock {
        let policy = DeviceAuthenticationPolicyMock(
            canAuthenicateWithPasscode: true,
            canAuthenticateWithBiometrics: true,
        )
        policy.authenticateWithBiometricsHandler = { _ in throw error }
        return policy
    }
}

@MainActor
private final class CallCounter {
    private(set) var callCount = 0

    func increment() {
        callCount += 1
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

    /// Waits (for up to 5 seconds) until `count` prompts have been shown in all, and the latest is up.
    func waitForPrompt(count: Int = 1) async {
        let deadline = ContinuousClock.now + .seconds(5)
        while promptCount < count || pending.isEmpty, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }

    func answer(_ authenticated: Bool) {
        guard pending.isNotEmpty else {
            Issue.record("No prompt is up to answer")
            return
        }
        pending.removeFirst().resume(returning: authenticated)
    }

    func answer(throwing error: any Error) {
        guard pending.isNotEmpty else {
            Issue.record("No prompt is up to answer")
            return
        }
        pending.removeFirst().resume(throwing: error)
    }
}
