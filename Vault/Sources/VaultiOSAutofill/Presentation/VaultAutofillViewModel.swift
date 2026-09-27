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
        /// With device authentication, then the App Lock Password if the vault's encrypted.
        case available
        /// The extension can't open the vault, so the user has to open Vault instead.
        case needsTheApp(NeedsTheAppReason)
    }

    enum NeedsTheAppReason: Equatable {
        /// The vault's encrypted, and the extension hasn't the memory to derive its key or save a change.
        case notEnoughMemory
        /// The vault's being converted, rekeyed or erased, the password's off (until VAULT-50), or its state can't be
        /// read.
        case unavailable
    }

    private(set) var feature: DisplayedFeature?
    let localSettings: LocalSettings
    /// The extension's own copy of the app lock, made for this request: it starts locked, and locks as soon as the
    /// sheet goes.
    let appLock: AppLockService
    private(set) var unlockAvailability: UnlockAvailability
    private let passwordService: (any AutofillPasswordUnlocking)?
    private let purgeVaultContents: @MainActor () async -> Void

    /// - Parameters:
    ///   - storage: How the vault is stored, as this request finds it.
    ///   - purgeVaultContents: Forgets everything the extension read from the vault.
    init(
        localSettings: LocalSettings,
        storage: AutofillVaultStorage,
        appLockSettings: AppLockSettingsStore,
        authenticationService: DeviceAuthenticationService,
        purgeVaultContents: @escaping @MainActor () async -> Void,
    ) {
        let passwordService: (any AutofillPasswordUnlocking)? = if case let .encrypted(service) = storage {
            service
        } else {
            nil
        }
        self.localSettings = localSettings
        self.passwordService = passwordService
        self.purgeVaultContents = purgeVaultContents
        appLock = AppLockService(
            settings: appLockSettings,
            authenticationService: authenticationService,
            passwordService: passwordService,
            delay: .immediately,
            purgeSensitiveData: {
                Task {
                    await passwordService?.lockVault()
                }
            },
        )
        unlockAvailability = switch storage {
        case .plain: .available
        case .encrypted: .checking
        case .unavailable: .needsTheApp(.unavailable)
        }
        passwordService?.onNotEnoughMemory = { [weak self] in
            self?.unlockAvailability = .needsTheApp(.notEnoughMemory)
        }
    }

    /// Gets the sheet ready to unlock, before it shows or asks for anything.
    ///
    /// Unless the vault's plain, whatever the process read from it before is forgotten first: in an earlier request,
    /// or before the app turned encryption on. An encrypted vault is locked again, so no unlock carries over, then the
    /// sheet checks there's the memory to derive the key: an extension stopped mid-attempt for using too much would
    /// have counted a wrong password.
    func prepareToUnlock() async {
        switch unlockAvailability {
        case .checking:
            await passwordService?.lockVault()
            let hasHeadroom = (try? await passwordService?.hasMemoryHeadroomToUnlock()) ?? false
            // A check that failed along the way has already sent the user to the app.
            guard unlockAvailability == .checking else { return }
            unlockAvailability = hasHeadroom ? .available : .needsTheApp(.notEnoughMemory)
        case .needsTheApp:
            await purgeVaultContents()
        case .available:
            break
        }
    }

    /// Locks an encrypted vault again at the end of the request, before the sheet goes: its keys and everything read
    /// from it go with it.
    func endRequest() async {
        await passwordService?.lockVault()
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
