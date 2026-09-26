import Combine
import Foundation
import VaultFeed
import VaultSettings

@MainActor
@Observable
final class VaultAutofillViewModel {
    enum DisplayedFeature: Equatable {
        case setupConfiguration
        case showAllCodesSelector
        case unimplemented(String)
    }

    enum RequestCancelReason: Equatable {
        case userCancelled
    }

    /// Whether the codes can be unlocked in the sheet.
    enum UnlockAvailability: Equatable {
        /// Still finding out.
        case checking
        /// With device authentication, then the App Lock Password if it's set.
        case available
        /// The vault needs the App Lock Password, and the extension hasn't the memory to derive its key: the user
        /// has to open Vault instead.
        case needsTheApp
    }

    private(set) var feature: DisplayedFeature?
    let localSettings: LocalSettings
    /// The extension's own copy of the app lock: each time the extension comes up with the lock on, it starts locked.
    let appLock: AppLockService
    private(set) var unlockAvailability: UnlockAvailability
    private let hasMemoryHeadroomToUnlock: (@MainActor () async -> Bool)?

    /// - Parameter hasMemoryHeadroomToUnlock: Whether the extension has the memory to derive the App Lock Password's
    ///   key, while the vault is encrypted. `nil` while it's plain, when there's no key to derive.
    init(
        localSettings: LocalSettings,
        appLock: AppLockService,
        hasMemoryHeadroomToUnlock: (@MainActor () async -> Bool)? = nil,
    ) {
        self.localSettings = localSettings
        self.appLock = appLock
        self.hasMemoryHeadroomToUnlock = hasMemoryHeadroomToUnlock
        unlockAvailability = hasMemoryHeadroomToUnlock == nil ? .available : .checking
    }

    /// Finds out whether the sheet can unlock the vault, before it asks for anything: an extension that ran out of
    /// memory deriving the key would be stopped by the system, mid-attempt.
    func checkUnlockAvailability() async {
        guard let hasMemoryHeadroomToUnlock else {
            unlockAvailability = .available
            return
        }
        unlockAvailability = await hasMemoryHeadroomToUnlock() ? .available : .needsTheApp
    }

    func show(feature: DisplayedFeature) {
        self.feature = feature
    }

    let configurationDismissSubject = PassthroughSubject<Void, Never>()

    var configurationDismissPublisher: any Publisher<Void, Never> {
        configurationDismissSubject
    }

    let textToInsertSubject = PassthroughSubject<String, Never>()

    var textToInsertPublisher: some Publisher<String, Never> {
        // Don't insert empty strings.
        textToInsertSubject.filter(\.isNotBlank)
    }

    let cancelRequestSubject = PassthroughSubject<RequestCancelReason, Never>()

    var cancelRequestPublisher: some Publisher<RequestCancelReason, Never> {
        cancelRequestSubject
    }

    func dismissConfiguration() {
        configurationDismissSubject.send()
    }
}
