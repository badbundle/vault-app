import Combine
import Foundation
import FoundationExtensions
import SwiftUI
import TestHelpers
import Testing
import UIKit
import VaultSettings
@testable import VaultFeed
@testable import VaultiOSAutofill

@MainActor
struct VaultAutofillViewModelTests {
    @Test
    func init_displaysNoFeature() throws {
        let sut = try makeSUT()

        #expect(sut.feature == nil)
    }

    @Test
    func show_setsDisplayedFeature() throws {
        let sut = try makeSUT()

        sut.show(feature: .showAllCodesSelector)

        #expect(sut.feature == .showAllCodesSelector)
    }

    @Test
    func dismissConfiguration_publishesDismiss() throws {
        let sut = try makeSUT()
        var dismissCount = 0
        let cancellable = sut.configurationDismissPublisher.sink { dismissCount += 1 }
        defer { cancellable.cancel() }

        sut.dismissConfiguration()

        #expect(dismissCount == 1)
    }

    @Test
    func textToInsertPublisher_filtersBlankStrings() throws {
        let sut = try makeSUT()
        var received = [String]()
        let cancellable = sut.textToInsertPublisher.sink { received.append($0) }
        defer { cancellable.cancel() }

        sut.textToInsertSubject.send("123456")
        sut.textToInsertSubject.send("")
        sut.textToInsertSubject.send("   ")
        sut.textToInsertSubject.send("654321")

        #expect(received == ["123456", "654321"])
    }

    @Test
    func cancelRequestPublisher_forwardsReason() throws {
        let sut = try makeSUT()
        var received = [VaultAutofillViewModel.RequestCancelReason]()
        let cancellable = sut.cancelRequestPublisher.sink { received.append($0) }
        defer { cancellable.cancel() }

        sut.cancelRequestSubject.send(.userCancelled)

        #expect(received == [.userCancelled])
    }
}

// MARK: - Unlocking

extension VaultAutofillViewModelTests {
    @Test
    func plainVault_unlocksWithDeviceAuthenticationAlone() async throws {
        let sut = try makeSUT(storage: .plain)

        await sut.prepareToUnlock()

        #expect(sut.unlockAvailability == .available)
        #expect(!sut.appLock.isPasswordSet)
    }

    /// Never Face ID alone while the password is on (MANIFESTO C4).
    @Test
    func passwordOn_asksForThePasswordAfterDeviceAuthentication() async throws {
        let sut = try makeSUT(storage: .password, vaultService: FakeAutofillVaultService())
        await sut.prepareToUnlock()

        await sut.appLock.unlock()

        #expect(sut.appLock.isPasswordSet)
        #expect(sut.appLock.state == .locked(.init(step: .password)))
    }

    @Test
    func passwordOn_isCheckedBeforeAnythingIsAsked() throws {
        let sut = try makeSUT(storage: .password, vaultService: FakeAutofillVaultService())

        #expect(sut.unlockAvailability == .checking)
    }

    /// An unlock left from an earlier request, and anything read then, don't carry over.
    @Test
    func prepareToUnlock_passwordOn_locksFirst() async throws {
        let service = FakeAutofillVaultService()
        let sut = try makeSUT(storage: .password, vaultService: service)

        await sut.prepareToUnlock()

        #expect(service.log == ["lock"])
        #expect(sut.unlockAvailability == .available)
    }

    /// Deriving the key without the memory would get the extension stopped mid-attempt, having counted a wrong one.
    @Test
    func prepareToUnlock_passwordOnWithoutTheMemory_needsTheApp() async throws {
        let sut = try makeSUT(storage: .password, vaultService: FakeAutofillVaultService(headroom: .notEnough))

        await sut.prepareToUnlock()

        #expect(sut.unlockAvailability == .needsTheApp(.notEnoughMemory))
    }

    /// Checked again before the password is tried, and before any save: either sends the user to the app.
    @Test
    func runningOutOfMemoryLater_needsTheApp() async throws {
        let service = FakeAutofillVaultService()
        let sut = try makeSUT(storage: .password, vaultService: service)
        await sut.prepareToUnlock()

        service.runOutOfMemory()

        #expect(sut.unlockAvailability == .needsTheApp(.notEnoughMemory))
    }

    @Test
    func unavailableVault_needsTheAppAndForgetsEarlierReads() async throws {
        let purges = Counter()
        let sut = try makeSUT(storage: .unavailable, purges: purges)

        await sut.prepareToUnlock()

        #expect(sut.unlockAvailability == .needsTheApp(.unavailable))
        #expect(purges.count == 1)
    }

    /// A process that served a request while the vault was plain serves the next one, after the app turned encryption
    /// on, as encrypted: it never shows what it read before on device authentication alone.
    @Test
    func requestAfterEncryptionIsTurnedOn_asksForThePasswordAndLocksFirst() async throws {
        let first = try makeSUT(storage: .plain)
        await first.prepareToUnlock()
        await first.appLock.unlock()
        #expect(first.appLock.state == .unlocked)

        let service = FakeAutofillVaultService()
        let second = try makeSUT(storage: .password, vaultService: service)
        await second.prepareToUnlock()
        await second.appLock.unlock()

        #expect(service.lockCount == 1)
        #expect(second.appLock.state == .locked(.init(step: .password)))
    }

    /// Whatever an earlier request in this process opened is locked first, whatever the mode now: after an erase, a
    /// plain request mustn't find the erased vault still open.
    @Test(arguments: [AutofillVaultStorage.plain, .unavailable])
    func prepareToUnlock_earlierServiceInThisProcess_locksItFirst(storage: AutofillVaultStorage) async throws {
        let earlier = FakeAutofillVaultService()
        let sut = try makeSUT(storage: storage, vaultService: earlier)

        if storage == .plain {
            #expect(sut.unlockAvailability == .checking)
        }
        await sut.prepareToUnlock()

        #expect(earlier.log == ["lock"])
        #expect(earlier.deviceKeyOpenCount == 0)
    }

    // MARK: - Password off

    /// With the password off, the device key opens the vault, and device authentication is all it takes: no password
    /// step, as for a plain vault. It's opened only once that's done.
    @Test
    func passwordOff_opensWithTheDeviceKeyOnlyAfterDeviceAuthentication() async throws {
        let service = FakeAutofillVaultService()
        let sut = try makeSUT(storage: .deviceKey, vaultService: service, isAppLockEnabled: true)

        await sut.prepareToUnlock()
        #expect(sut.unlockAvailability == .available)
        #expect(service.deviceKeyOpenCount == 0)
        await sut.getVaultReadyToShow()
        #expect(service.deviceKeyOpenCount == 0, "Nothing's shown before the sheet's lock is unlocked")

        await sut.appLock.unlock()
        #expect(sut.appLock.state == .unlocked)
        #expect(!sut.appLock.isPasswordSet)
        await sut.getVaultReadyToShow()

        #expect(service.log == ["lock", "open with the device key"])
        #expect(sut.isVaultReady)
    }

    @Test
    func passwordOff_withoutTheMemory_needsTheApp() async throws {
        let service = FakeAutofillVaultService(headroom: .notEnough)
        let sut = try makeSUT(storage: .deviceKey, vaultService: service)

        await sut.prepareToUnlock()

        #expect(sut.unlockAvailability == .needsTheApp(.notEnoughMemory))
        #expect(service.deviceKeyOpenCount == 0)
    }

    /// Such as while the device is locked after starting up, when the device key can't be read.
    @Test
    func passwordOff_deviceKeyCannotOpenIt_needsTheApp() async throws {
        let service = FakeAutofillVaultService()
        service.failsToOpenWithDeviceKey = true
        let purges = Counter()
        let sut = try makeSUT(storage: .deviceKey, vaultService: service, purges: purges)
        await sut.prepareToUnlock()

        await sut.getVaultReadyToShow()

        #expect(sut.unlockAvailability == .needsTheApp(.unavailable))
        #expect(!sut.isVaultReady)
        #expect(purges.count == 1)
    }

    /// The app turned the password on, or started an erase, since the request began: the sheet sends the user to
    /// Vault, and opens nothing.
    @Test(arguments: [VaultAccessMode.password, .unavailable, .plain])
    func passwordOff_modeChangesBeforePreparing_needsTheAppAndOpensNothing(mode: VaultAccessMode) async throws {
        let service = FakeAutofillVaultService()
        let accessMode = SharedMutex(VaultAccessMode.deviceKey)
        let purges = Counter()
        let sut = try makeSUT(storage: .deviceKey, vaultService: service, accessMode: accessMode, purges: purges)
        await sut.prepareToUnlock()
        #expect(sut.unlockAvailability == .available)

        accessMode.modify { $0 = mode }
        await sut.prepareToUnlock()

        #expect(sut.unlockAvailability == .needsTheApp(.unavailable))
        #expect(service.deviceKeyOpenCount == 0)
        #expect(purges.count == 1)
    }

    /// The sheet was left open in another app while the user turned the password on in Vault. Coming back, device
    /// authentication alone mustn't show the vault (MANIFESTO C4).
    @Test(arguments: [VaultAccessMode.password, .unavailable])
    func passwordOff_modeChangesBetweenDeviceAuthenticationAndShowing_opensNothing(mode: VaultAccessMode) async throws {
        let service = FakeAutofillVaultService()
        let accessMode = SharedMutex(VaultAccessMode.deviceKey)
        let sut = try makeSUT(
            storage: .deviceKey,
            vaultService: service,
            isAppLockEnabled: true,
            accessMode: accessMode,
        )
        await sut.prepareToUnlock()
        await sut.appLock.unlock()

        accessMode.modify { $0 = mode }
        await sut.getVaultReadyToShow()

        #expect(sut.unlockAvailability == .needsTheApp(.unavailable))
        #expect(!sut.isVaultReady)
        #expect(service.deviceKeyOpenCount == 0)
    }

    /// The app turned the password on while the vault was being opened: it's locked again straight away, and nothing
    /// shows.
    @Test
    func passwordOff_modeChangesWhileOpening_locksItAgain() async throws {
        let service = FakeAutofillVaultService()
        let accessMode = SharedMutex(VaultAccessMode.deviceKey)
        service.whileOpening = { accessMode.modify { $0 = .password } }
        let sut = try makeSUT(storage: .deviceKey, vaultService: service, accessMode: accessMode)
        await sut.prepareToUnlock()

        await sut.getVaultReadyToShow()

        #expect(service.log == ["lock", "open with the device key", "lock"])
        #expect(sut.unlockAvailability == .needsTheApp(.unavailable))
        #expect(!sut.isVaultReady)
    }

    /// When the sheet's lock locks, the vault locks, and the codes hide until it's opened again, after device
    /// authentication.
    @Test
    func passwordOff_sheetLocks_locksAndOpensAgainOnlyOnceUnlocked() async throws {
        let service = FakeAutofillVaultService()
        let sut = try makeSUT(storage: .deviceKey, vaultService: service, isAppLockEnabled: true)
        await sut.prepareToUnlock()
        await sut.appLock.unlock()
        await sut.getVaultReadyToShow()
        let lockCount = sut.lockCount

        sut.appLock.scenePhaseDidChange(to: .background)

        #expect(!sut.isVaultReady)
        #expect(sut.lockCount == lockCount + 1)
        await sut.endRequest()
        #expect(service.log == ["lock", "open with the device key", "lock", "lock"])
        await sut.getVaultReadyToShow()
        #expect(service.deviceKeyOpenCount == 1, "Not before device authentication")

        await sut.appLock.unlock()
        await sut.getVaultReadyToShow()
        #expect(service.deviceKeyOpenCount == 2)
        #expect(sut.isVaultReady)
    }

    /// With the app lock off, nothing asks for device authentication, so going to another app, which could be Vault,
    /// locks the vault anyway. It's checked, and opened again, only once the sheet is back.
    @Test
    func passwordOff_appLockOff_leavingTheSheet_locksItAndChecksAgainOnReturn() async throws {
        let service = FakeAutofillVaultService()
        let accessMode = SharedMutex(VaultAccessMode.deviceKey)
        let sut = try makeSUT(storage: .deviceKey, vaultService: service, accessMode: accessMode)
        await sut.prepareToUnlock()
        await sut.getVaultReadyToShow()
        #expect(sut.isVaultReady)

        sut.scenePhaseDidChange(to: .background)
        await sut.getVaultReadyToShow()
        #expect(!sut.isVaultReady)
        #expect(service.deviceKeyOpenCount == 1, "Not while the sheet's away")

        accessMode.modify { $0 = .password }
        sut.scenePhaseDidChange(to: .active)
        await sut.getVaultReadyToShow()

        #expect(sut.unlockAvailability == .needsTheApp(.unavailable))
        #expect(!sut.isVaultReady)
        #expect(service.deviceKeyOpenCount == 1)
    }

    /// A check the sheet no longer wants, as its view went, doesn't overrule the next one.
    @Test
    func prepareToUnlock_cancelled_leavesTheSheetForTheNextCheck() async throws {
        let service = FakeAutofillVaultService(headroom: .answersWhenTold)
        let sut = try makeSUT(storage: .password, vaultService: service)
        let cancelled = Task { await sut.prepareToUnlock() }
        try await service.waitForHeadroomCheck()

        cancelled.cancel()
        service.answerHeadroomChecks(false)
        await cancelled.value
        #expect(sut.unlockAvailability == .checking)

        let next = Task { await sut.prepareToUnlock() }
        try await service.waitForHeadroomCheck()
        service.answerHeadroomChecks(true)
        await next.value
        #expect(sut.unlockAvailability == .available)
    }

    // MARK: - Locking

    @Test(arguments: [AutofillVaultStorage.deviceKey, .password])
    func endRequest_locksTheVault(storage: AutofillVaultStorage) async throws {
        let service = FakeAutofillVaultService()
        let sut = try makeSUT(storage: storage, vaultService: service)

        await sut.endRequest()

        #expect(service.lockCount == 1)
    }

    // MARK: - The device locking

    /// Password on: the device locking with the sheet open locks the sheet and the vault, and hides the codes, even if
    /// the sheet never hears it's left the screen. It takes device authentication and the password to show them again.
    @Test
    func passwordOn_deviceLocks_locksTheSheetAndTheVault() async throws {
        let service = FakeAutofillVaultService()
        let sut = try makeSUT(storage: .password, vaultService: service)
        await sut.prepareToUnlock()
        await sut.appLock.unlock()
        await sut.appLock.unlock(password: "correct horse")
        await sut.getVaultReadyToShow()
        #expect(sut.isVaultReady)
        let lockCount = service.lockCount
        let notificationCenter = NotificationCenter()
        let observer = sut.lockWhenTheDeviceLocks(notificationCenter: notificationCenter)
        defer { notificationCenter.removeObserver(observer) }

        notificationCenter.post(name: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil)
        try await waitUntil { sut.appLock.isLocked }
        await sut.appLock.vaultLock?.value

        #expect(!sut.isVaultReady)
        #expect(service.lockCount > lockCount)
        #expect(sut.appLock.state == .locked(.init(step: .deviceAuthentication)))
        await sut.appLock.unlock()
        await sut.getVaultReadyToShow()
        #expect(sut.appLock.state == .locked(.init(step: .password)))
        #expect(!sut.isVaultReady)
    }

    /// Password off, with App Lock on: the sheet locks as it does leaving the screen, and the vault with it.
    @Test
    func passwordOff_appLockOn_deviceLocks_locksTheSheetAndTheVault() async throws {
        let service = FakeAutofillVaultService()
        let sut = try makeSUT(storage: .deviceKey, vaultService: service, isAppLockEnabled: true)
        await sut.prepareToUnlock()
        await sut.appLock.unlock()
        await sut.getVaultReadyToShow()
        #expect(sut.isVaultReady)
        let lockCount = sut.lockCount
        let notificationCenter = NotificationCenter()
        let observer = sut.lockWhenTheDeviceLocks(notificationCenter: notificationCenter)
        defer { notificationCenter.removeObserver(observer) }

        notificationCenter.post(name: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil)
        try await waitUntil { sut.appLock.isLocked }

        #expect(!sut.isVaultReady)
        #expect(sut.lockCount == lockCount + 1)
        await sut.endRequest()
        #expect(service.log == ["lock", "open with the device key", "lock", "lock"])
    }

    /// Password off, with App Lock off: nothing locks, as in the app, where only the password's keys are taken out of
    /// memory as the device locks.
    @Test
    func passwordOff_appLockOff_deviceLocks_leavesTheSheetAsItIs() async throws {
        let service = FakeAutofillVaultService()
        let sut = try makeSUT(storage: .deviceKey, vaultService: service)
        await sut.prepareToUnlock()
        await sut.getVaultReadyToShow()
        #expect(sut.isVaultReady)
        let notificationCenter = NotificationCenter()
        let observer = sut.lockWhenTheDeviceLocks(notificationCenter: notificationCenter)
        defer { notificationCenter.removeObserver(observer) }

        notificationCenter.post(name: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil)
        try await Task.sleep(for: .milliseconds(100))

        #expect(sut.isVaultReady)
        #expect(sut.appLock.state == .unlocked)
        #expect(service.lockCount == 1, "Only the lock as the sheet got ready")
    }

    /// Password on: the sheet leaving the screen, as it does when the device locks with it open, locks the vault and
    /// hides the codes. Back on the screen, it takes device authentication and the password again.
    @Test
    func passwordOn_sheetLeavesTheScreen_locksTheVaultAndAsksForThePasswordAgain() async throws {
        let service = FakeAutofillVaultService()
        let sut = try makeSUT(storage: .password, vaultService: service)
        await sut.prepareToUnlock()
        await sut.appLock.unlock()
        await sut.appLock.unlock(password: "correct horse")
        await sut.getVaultReadyToShow()
        #expect(sut.isVaultReady)
        let lockCount = service.lockCount

        // As SwiftUI tells the sheet, and its lock (`AppLockGate`).
        sut.scenePhaseDidChange(to: .background)
        sut.appLock.scenePhaseDidChange(to: .background)
        await sut.appLock.vaultLock?.value

        #expect(!sut.isVaultReady)
        #expect(service.lockCount > lockCount)
        #expect(sut.appLock.state == .locked(.init(step: .deviceAuthentication)))

        sut.scenePhaseDidChange(to: .active)
        sut.appLock.scenePhaseDidChange(to: .active)
        await sut.appLock.automaticUnlock?.value
        await sut.getVaultReadyToShow()

        #expect(sut.appLock.state == .locked(.init(step: .password)))
        #expect(!sut.isVaultReady)
        await sut.appLock.unlock(password: "correct horse")
        await sut.getVaultReadyToShow()
        #expect(sut.isVaultReady)
    }

    /// A sheet dismissed and opened again starts locked, asking for device authentication and the password: nothing
    /// carries over from the last request, whose vault was locked as it went.
    @Test
    func passwordOn_sheetDismissedAndOpenedAgain_asksForThePasswordAgain() async throws {
        let service = FakeAutofillVaultService()
        let first = try makeSUT(storage: .password, vaultService: service)
        await first.prepareToUnlock()
        await first.appLock.unlock()
        await first.appLock.unlock(password: "correct horse")
        await first.getVaultReadyToShow()
        #expect(first.isVaultReady)

        // Dismissed, as `viewDidDisappear` has it.
        await first.endRequest()
        #expect(service.log.last == "lock")
        let lockCount = service.lockCount

        let second = try makeSUT(storage: .password, vaultService: service)
        #expect(second.appLock.state == .locked(.init(step: .deviceAuthentication)))
        await second.prepareToUnlock()
        #expect(service.lockCount == lockCount + 1)
        await second.appLock.unlock()
        await second.getVaultReadyToShow()

        #expect(second.appLock.state == .locked(.init(step: .password)))
        #expect(!second.isVaultReady)
    }

    /// Whatever delay the user chose for the app, the extension locks as soon as it leaves the screen.
    @Test
    func appLock_locksStraightAway() throws {
        let settings = try AppLockSettingsStore(userDefaults: .nonPersistent())
        settings.isEnabled = true
        settings.delay = .fifteenMinutes

        let sut = try makeSUT(storage: .plain, appLockSettings: settings)

        #expect(sut.appLock.delay == .immediately)
    }

    /// A plain vault the app encrypted since the request began isn't shown on device authentication alone either.
    @Test
    func plainVault_encryptedBeforeShowing_needsTheApp() async throws {
        let accessMode = SharedMutex(VaultAccessMode.plain)
        let sut = try makeSUT(storage: .plain, isAppLockEnabled: true, accessMode: accessMode)
        await sut.prepareToUnlock()
        await sut.appLock.unlock()

        accessMode.modify { $0 = .password }
        await sut.getVaultReadyToShow()

        #expect(sut.unlockAvailability == .needsTheApp(.unavailable))
        #expect(!sut.isVaultReady)
    }
}

// MARK: - Helpers

extension VaultAutofillViewModelTests {
    /// - Parameter accessMode: How the vault can be opened now. By default, as `storage` found it.
    private func makeSUT(
        storage: AutofillVaultStorage = .plain,
        vaultService: FakeAutofillVaultService? = nil,
        isAppLockEnabled: Bool = false,
        accessMode: SharedMutex<VaultAccessMode>? = nil,
        appLockSettings: AppLockSettingsStore? = nil,
        purges: Counter = Counter(),
    ) throws -> VaultAutofillViewModel {
        let settings = try appLockSettings ?? AppLockSettingsStore(userDefaults: .nonPersistent())
        if isAppLockEnabled {
            settings.isEnabled = true
        }
        let accessMode = accessMode ?? SharedMutex(Self.accessMode(for: storage))
        return try VaultAutofillViewModel(
            localSettings: LocalSettings(defaults: Defaults.nonPersistent()),
            storage: storage,
            vaultService: vaultService,
            currentAccessMode: { accessMode.value },
            appLockSettings: settings,
            authenticationService: DeviceAuthenticationService(policy: .alwaysAllow),
            purgeVaultContents: { purges.increment() },
        )
    }

    /// Waits for a notification delivered on the main queue, up to a couple of seconds.
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

    private static func accessMode(for storage: AutofillVaultStorage) -> VaultAccessMode {
        switch storage {
        case .plain: .plain
        case .deviceKey: .deviceKey
        case .password: .password
        case .unavailable: .unavailable
        }
    }
}

@MainActor
private final class Counter {
    private(set) var count = 0

    func increment() {
        count += 1
    }
}
