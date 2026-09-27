import Combine
import Foundation
import SwiftUI
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
    enum UnlockAvailability: Equatable, Sendable {
        /// Still finding out.
        case checking
        /// With device authentication, if the app lock is on, then the App Lock Password if it's set.
        case available
        /// The extension can't open the vault, so the user has to open Vault instead.
        case needsTheApp(NeedsTheAppReason)
    }

    enum NeedsTheAppReason: Equatable, Sendable {
        /// The vault's encrypted, and the extension hasn't the memory to open it or save a change.
        case notEnoughMemory
        /// The vault's being converted, rekeyed or erased, its state can't be read, or it isn't stored the way it was
        /// when the request began.
        case unavailable
    }

    private(set) var feature: DisplayedFeature?
    let localSettings: LocalSettings
    /// The extension's own copy of the app lock, made for this request: it starts locked, and locks as soon as the
    /// sheet goes.
    let appLock: AppLockService
    private(set) var unlockAvailability: UnlockAvailability
    /// Whether the codes can show, once the sheet's lock is unlocked: once the vault's been checked to be stored as
    /// this request found it, and opened, with the device key.
    private(set) var isVaultReady = false
    /// Counts the times the vault's been locked, and the codes hidden, since the request began. Getting it ready again
    /// starts over each time.
    private(set) var lockCount = 0
    private let storage: AutofillVaultStorage
    private let vaultService: (any AutofillVaultUnlocking)?
    private let purgeVaultContents: @MainActor () async -> Void
    /// How the vault can be opened now, read afresh each time.
    private let currentAccessMode: @Sendable () -> VaultAccessMode
    /// Whether the vault the device key opens is open, since it was last locked.
    private var isOpenWithDeviceKey = false
    /// Whether the sheet is off the screen, as when the user's gone to another app, which could be Vault.
    private var isAway = false
    /// The last of the operations on the vault: locking it, and checking how it's stored and opening it. They run one
    /// at a time, in order, so a lock can't be overtaken by an open that started before it.
    private var lastVaultOperation: Task<Void, Never>?

    /// - Parameters:
    ///   - storage: How the vault is stored, as this request finds it.
    ///   - vaultService: What opens the encrypted vault in this process: for an encrypted vault, and for any other if
    ///     an earlier request made one, so what that opened is locked first.
    ///   - currentAccessMode: How the vault can be opened now. The app can change it while the sheet is open.
    ///   - purgeVaultContents: Forgets everything the extension read from the vault.
    init(
        localSettings: LocalSettings,
        storage: AutofillVaultStorage,
        vaultService: (any AutofillVaultUnlocking)?,
        currentAccessMode: @escaping @Sendable () -> VaultAccessMode,
        appLockSettings: AppLockSettingsStore,
        authenticationService: DeviceAuthenticationService,
        purgeVaultContents: @escaping @MainActor () async -> Void,
    ) {
        let didLock = LockHandler()
        self.localSettings = localSettings
        self.storage = storage
        self.vaultService = vaultService
        self.currentAccessMode = currentAccessMode
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
            self?.lockTheVault()
        }
        vaultService?.onNotEnoughMemory = { [weak self] in
            self?.unlockAvailability = .needsTheApp(.notEnoughMemory)
        }
    }

    /// Gets the sheet ready to unlock, before it shows or asks for anything.
    ///
    /// Whatever an earlier request opened in this process is locked first, whatever the mode now, and a vault the
    /// extension can't open is forgotten: nothing read before, in an earlier request or before the app changed how the
    /// vault's stored, carries over. If the vault isn't stored as this request found it any more, the sheet sends the
    /// user to Vault.
    ///
    /// An encrypted vault needs the memory to open: an extension stopped mid-attempt for using too much would have
    /// counted a wrong password. Nothing's opened yet: with the device key, that waits for device authentication
    /// (`getVaultReadyToShow()`).
    func prepareToUnlock() async {
        lockTheVault()
        let availability = await runVaultOperation { [self] () -> UnlockAvailability? in
            guard isStoredAsTheRequestFoundIt else {
                await purgeVaultContents()
                return .needsTheApp(.unavailable)
            }
            switch storage {
            case .plain:
                return .available
            case .password, .deviceKey:
                let hasHeadroom = (try? await vaultService?.hasMemoryHeadroomToUnlock()) ?? false
                return hasHeadroom ? .available : .needsTheApp(.notEnoughMemory)
            case .unavailable:
                await purgeVaultContents()
                return nil
            }
        }.value
        // A check the sheet no longer wants, as its view has gone, mustn't overrule a later one.
        guard !Task.isCancelled, let availability else { return }
        settle(availability)
    }

    /// Gets the vault ready for the codes to show, once the sheet's lock is unlocked: after device authentication, and
    /// the password if it's on.
    ///
    /// It checks again that the vault's stored as this request found it: the app can turn the password on, or erase
    /// the vault, while the sheet is open. With the device key, it opens the vault only now, and checks again once it
    /// has. If the vault isn't stored the same way, it's locked and forgotten, and the sheet sends the user to Vault.
    func getVaultReadyToShow() async {
        // Never before the sheet's lock is unlocked: device authentication comes first.
        guard !isVaultReady, !isAway, !appLock.isLocked else { return }
        let lockCount = lockCount
        let outcome = await runVaultOperation { [self] () -> ReadyOutcome in
            guard lockCount == self.lockCount else { return .lockedMeanwhile }
            guard isStoredAsTheRequestFoundIt else { return await forgetTheVault() }
            guard storage == .deviceKey, !isOpenWithDeviceKey else { return .ready }
            do {
                try await vaultService?.openWithDeviceKey()
            } catch is AutofillVaultService.NotEnoughMemoryError {
                return .needsTheApp(.notEnoughMemory)
            } catch {
                return await forgetTheVault()
            }
            isOpenWithDeviceKey = true
            // Opening takes a while, and the app may have changed how the vault's stored meanwhile. Every call to the
            // vault checks too (`VaultAccessGuard`), but the sheet shouldn't show an empty vault.
            guard isStoredAsTheRequestFoundIt else { return await forgetTheVault() }
            return .ready
        }.value
        switch outcome {
        case .ready:
            // A lock since then hides the codes again, and getting ready starts over.
            if lockCount == self.lockCount {
                isVaultReady = true
            }
        case let .needsTheApp(reason):
            unlockAvailability = .needsTheApp(reason)
        case .lockedMeanwhile:
            break
        }
    }

    /// Where the sheet is, as SwiftUI tells it. Going to another app, which could be Vault, locks the vault and hides
    /// the
    /// codes, even with the app lock off, so the vault's checked again when the sheet comes back.
    func scenePhaseDidChange(to phase: ScenePhase) {
        switch phase {
        case .background:
            isAway = true
            lockTheVault()
        case .active where isAway:
            isAway = false
            // Starts getting the vault ready again, now it can be.
            lockTheVault()
        default:
            break
        }
    }

    /// Locks the vault again at the end of the request, before the sheet goes: its keys and everything read from it go
    /// with it.
    func endRequest() async {
        await lockTheVault().value
    }

    private enum ReadyOutcome: Sendable {
        case ready
        case needsTheApp(NeedsTheAppReason)
        case lockedMeanwhile
    }

    /// Whether the vault is still stored the way it was when the request began, which is what the sheet was set up
    /// for: with the password, say, or not.
    private var isStoredAsTheRequestFoundIt: Bool {
        AutofillVaultStorage(currentAccessMode()) == storage
    }

    /// Locks the vault and forgets everything read from it, for the sheet to send the user to Vault.
    private func forgetTheVault() async -> ReadyOutcome {
        await vaultService?.lockVault()
        isOpenWithDeviceKey = false
        await purgeVaultContents()
        return .needsTheApp(.unavailable)
    }

    /// Settles the sheet: it can always be sent to Vault, but it's only made available from checking, unless something
    /// along the way has already sent the user to the app.
    private func settle(_ availability: UnlockAvailability) {
        switch availability {
        case .needsTheApp:
            unlockAvailability = availability
        case .available, .checking:
            guard unlockAvailability == .checking else { return }
            unlockAvailability = availability
        }
    }

    /// Hides the codes, and locks the vault, once whatever's underway on it has finished. As when the sheet's lock
    /// locks, or the sheet leaves the screen.
    @discardableResult
    private func lockTheVault() -> Task<Void, Never> {
        lockCount += 1
        isVaultReady = false
        return runVaultOperation { [self] in
            await vaultService?.lockVault()
            isOpenWithDeviceKey = false
        }
    }

    /// Runs `operation` on the vault once every one before it has finished.
    private func runVaultOperation<Result: Sendable>(
        _ operation: @escaping @MainActor () async -> Result,
    ) -> Task<Result, Never> {
        let previous = lastVaultOperation
        let task = Task { @MainActor in
            await previous?.value
            return await operation()
        }
        lastVaultOperation = Task { _ = await task.value }
        return task
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
