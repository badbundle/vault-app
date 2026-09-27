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
        /// Still finding out, or getting the vault ready.
        case checking
        /// With device authentication, if the app lock is on, then the App Lock Password if it's set.
        case available
        /// The extension can't open the vault, so the user has to open Vault instead.
        case needsTheApp(NeedsTheAppReason)
    }

    enum NeedsTheAppReason: Equatable {
        /// The vault's encrypted, and the extension hasn't the memory to open it or save a change.
        case notEnoughMemory
        /// The vault's being converted, rekeyed or erased, or its state can't be read.
        case unavailable
    }

    private(set) var feature: DisplayedFeature?
    let localSettings: LocalSettings
    /// The extension's own copy of the app lock, made for this request: it starts locked, and locks as soon as the
    /// sheet goes.
    let appLock: AppLockService
    private(set) var unlockAvailability: UnlockAvailability
    /// Changes whenever the sheet has to get the vault ready again, as after the sheet's lock locks.
    private(set) var preparation = 0
    private let storage: AutofillVaultStorage
    private let vaultService: (any AutofillVaultUnlocking)?
    private let purgeVaultContents: @MainActor () async -> Void
    /// Locking the vault since the sheet's lock locked, which getting it ready again waits for.
    private var pendingLock: Task<Void, Never>?

    /// - Parameters:
    ///   - storage: How the vault is stored, as this request finds it.
    ///   - vaultService: What opens the encrypted vault in this process: for an encrypted vault, and for any other if
    ///     an earlier request made one, so what that opened is locked first.
    ///   - purgeVaultContents: Forgets everything the extension read from the vault.
    init(
        localSettings: LocalSettings,
        storage: AutofillVaultStorage,
        vaultService: (any AutofillVaultUnlocking)?,
        appLockSettings: AppLockSettingsStore,
        authenticationService: DeviceAuthenticationService,
        purgeVaultContents: @escaping @MainActor () async -> Void,
    ) {
        let didLock = LockHandler()
        self.localSettings = localSettings
        self.storage = storage
        self.vaultService = vaultService
        self.purgeVaultContents = purgeVaultContents
        appLock = AppLockService(
            settings: appLockSettings,
            authenticationService: authenticationService,
            // Only the password step needs it: with the device key, device authentication is all it takes.
            passwordService: storage == .password ? vaultService : nil,
            delay: .immediately,
            purgeSensitiveData: { didLock.handle() },
        )
        unlockAvailability = switch storage {
        case .plain: vaultService == nil ? .available : .checking
        case .deviceKey, .password: .checking
        case .unavailable: .needsTheApp(.unavailable)
        }
        didLock.handler = { [weak self] in
            self?.appLockDidLock()
        }
        vaultService?.onNotEnoughMemory = { [weak self] in
            self?.unlockAvailability = .needsTheApp(.notEnoughMemory)
        }
    }

    /// Gets the sheet ready to unlock, before it shows or asks for anything.
    ///
    /// Whatever an earlier request opened in this process is locked first, whatever the mode now, and a vault the
    /// extension can't open is forgotten: nothing read before, in an earlier request or before the app changed how the
    /// vault's stored, carries over.
    ///
    /// - An encrypted vault needs the memory to open: an extension stopped mid-attempt for using too much would have
    ///   counted a wrong password.
    /// - With the password off, the device key opens the vault straight away, as the plain store is there to read.
    ///   The sheet still asks for device authentication before it shows anything, if the app lock is on.
    func prepareToUnlock() async {
        await pendingLock?.value
        await vaultService?.lockVault()
        switch storage {
        case .plain:
            finishChecking(as: .available)
        case .password:
            let hasHeadroom = (try? await vaultService?.hasMemoryHeadroomToUnlock()) ?? false
            finishChecking(as: hasHeadroom ? .available : .needsTheApp(.notEnoughMemory))
        case .deviceKey:
            do {
                try await vaultService?.openWithDeviceKey()
                finishChecking(as: .available)
            } catch is AutofillVaultService.NotEnoughMemoryError {
                finishChecking(as: .needsTheApp(.notEnoughMemory))
            } catch {
                finishChecking(as: .needsTheApp(.unavailable))
            }
        case .unavailable:
            await purgeVaultContents()
        }
    }

    /// Settles what's being checked, unless something along the way has already sent the user to the app.
    private func finishChecking(as availability: UnlockAvailability) {
        guard unlockAvailability == .checking else { return }
        unlockAvailability = availability
    }

    /// Locks the vault again at the end of the request, before the sheet goes: its keys and everything read from it go
    /// with it.
    func endRequest() async {
        await vaultService?.lockVault()
    }

    /// The sheet's lock locked, as when it left the screen: the vault locks straight away too. With the device key,
    /// it's opened again, once that's done, before device authentication is asked for again.
    private func appLockDidLock() {
        let vaultService = vaultService
        pendingLock = Task {
            await vaultService?.lockVault()
        }
        if storage == .deviceKey {
            unlockAvailability = .checking
            preparation += 1
        }
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

/// Passes on the app lock locking, to the view model made after the lock.
@MainActor
private final class LockHandler {
    var handler: (() -> Void)?

    func handle() {
        handler?()
    }
}
