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

// MARK: - Unlocking an encrypted vault

extension VaultAutofillViewModelTests {
    @Test
    func unlockAvailability_plainVault_isAvailableWithoutChecking() throws {
        let sut = try makeSUT()

        #expect(sut.unlockAvailability == .available)
    }

    @Test
    func unlockAvailability_encryptedVault_isCheckedBeforeAnythingIsAsked() throws {
        let sut = try makeSUT(hasMemoryHeadroomToUnlock: { true })

        #expect(sut.unlockAvailability == .checking)
    }

    @Test
    func checkUnlockAvailability_enoughMemory_isAvailable() async throws {
        let sut = try makeSUT(hasMemoryHeadroomToUnlock: { true })

        await sut.checkUnlockAvailability()

        #expect(sut.unlockAvailability == .available)
    }

    /// Deriving the key without the memory would get the extension stopped mid-attempt, so it sends the user to the
    /// app instead of asking for the password.
    @Test
    func checkUnlockAvailability_notEnoughMemory_needsTheApp() async throws {
        let sut = try makeSUT(hasMemoryHeadroomToUnlock: { false })

        await sut.checkUnlockAvailability()

        #expect(sut.unlockAvailability == .needsTheApp)
    }
}

// MARK: - Helpers

extension VaultAutofillViewModelTests {
    private func makeSUT(
        hasMemoryHeadroomToUnlock: (@MainActor () async -> Bool)? = nil,
    ) throws -> VaultAutofillViewModel {
        try VaultAutofillViewModel(
            localSettings: LocalSettings(defaults: Defaults.nonPersistent()),
            appLock: AppLockService(
                settings: AppLockSettingsStore(userDefaults: .nonPersistent()),
                authenticationService: DeviceAuthenticationService(policy: .alwaysAllow),
                purgeSensitiveData: {},
            ),
            hasMemoryHeadroomToUnlock: hasMemoryHeadroomToUnlock,
        )
    }
}
