import Combine
import Foundation
import FoundationExtensions
import TestHelpers
import Testing
import VaultFeed
import VaultSettings
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
    /// step, as for a plain vault.
    @Test
    func passwordOff_opensWithTheDeviceKeyAndAsksForNoPassword() async throws {
        let service = FakeAutofillVaultService()
        let sut = try makeSUT(storage: .deviceKey, vaultService: service, isAppLockEnabled: true)

        await sut.prepareToUnlock()
        await sut.appLock.unlock()

        #expect(service.log == ["lock", "open with the device key"])
        #expect(sut.unlockAvailability == .available)
        #expect(!sut.appLock.isPasswordSet)
        #expect(sut.appLock.state == .unlocked)
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
        let sut = try makeSUT(storage: .deviceKey, vaultService: service)

        await sut.prepareToUnlock()

        #expect(sut.unlockAvailability == .needsTheApp(.unavailable))
    }

    /// When the sheet's lock locks, the vault locks straight away, and it's opened again, once it has, before device
    /// authentication is asked for again.
    @Test
    func passwordOff_sheetLocks_getsTheVaultReadyAgain() async throws {
        let service = FakeAutofillVaultService()
        let sut = try makeSUT(storage: .deviceKey, vaultService: service, isAppLockEnabled: true)
        await sut.prepareToUnlock()
        await sut.appLock.unlock()
        let preparation = sut.preparation

        sut.appLock.scenePhaseDidChange(to: .background)

        #expect(sut.unlockAvailability == .checking)
        #expect(sut.preparation == preparation + 1)
        await sut.prepareToUnlock()
        #expect(service.log == ["lock", "open with the device key", "lock", "lock", "open with the device key"])
    }

    // MARK: - Locking

    @Test(arguments: [AutofillVaultStorage.deviceKey, .password])
    func endRequest_locksTheVault(storage: AutofillVaultStorage) async throws {
        let service = FakeAutofillVaultService()
        let sut = try makeSUT(storage: storage, vaultService: service)

        await sut.endRequest()

        #expect(service.lockCount == 1)
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
}

// MARK: - Helpers

extension VaultAutofillViewModelTests {
    private func makeSUT(
        storage: AutofillVaultStorage = .plain,
        vaultService: FakeAutofillVaultService? = nil,
        isAppLockEnabled: Bool = false,
        appLockSettings: AppLockSettingsStore? = nil,
        purges: Counter = Counter(),
    ) throws -> VaultAutofillViewModel {
        let settings = try appLockSettings ?? AppLockSettingsStore(userDefaults: .nonPersistent())
        if isAppLockEnabled {
            settings.isEnabled = true
        }
        return try VaultAutofillViewModel(
            localSettings: LocalSettings(defaults: Defaults.nonPersistent()),
            storage: storage,
            vaultService: vaultService,
            appLockSettings: settings,
            authenticationService: DeviceAuthenticationService(policy: .alwaysAllow),
            purgeVaultContents: { purges.increment() },
        )
    }
}

@MainActor
private final class Counter {
    private(set) var count = 0

    func increment() {
        count += 1
    }
}
