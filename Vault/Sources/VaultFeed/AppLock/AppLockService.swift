import Foundation
import LocalAuthentication

/// The app lock: when it's on, the whole app stays behind a lock screen until the user authenticates.
///
/// The app starts locked and locks again when it goes to the background, or, with a `delay`, when it comes back after
/// being in the background for at least that long. Going inactive (Control Center, the app switcher) doesn't lock the
/// app, but the scene covers the vault with a privacy cover (see `requiresPrivacyCover(in:)`) so it doesn't show in
/// the app switcher, whatever the delay.
///
/// Unlocking takes the user through `AppUnlockStep`s in order. Device authentication comes first, and it's asked for
/// automatically when the app comes to the foreground locked; a cancelled or failed try waits for the user to try again
/// with `unlock()`. When the App Lock Password is set, the password comes next, with `unlock(password:)`.
///
/// The App Lock Password is only offered with a `passwordService`, which the app doesn't have until the encrypted
/// vault's storage is in. It's set, changed and turned off here too, so the lock always knows whether to ask for it,
/// and a duress password is set here as well.
///
/// With erasing after failed passwords on (VAULT-34), the password service erases every vault at the threshold's wrong
/// password in a row. The lock screen then simply opens the fresh, empty vault, like a new install: it never says the
/// password was wrong first, and never how many attempts were left. Nothing waiting to open an item runs after an
/// erase, whenever it finishes. The lock itself stays on, asking for device authentication only: it's a choice the
/// user made for the device, not something of the vaults the erase removed, and whatever's added to the fresh vault
/// stays behind it.
///
/// Anything that would reveal the vault while it's locked, such as opening an item from a widget, waits in
/// `performWhenUnlocked(_:)` until the user has unlocked the app.
@MainActor
@Observable
public final class AppLockService {
    public private(set) var state: AppLockState
    /// Whether the app lock is on.
    public private(set) var isEnabled: Bool
    /// How long the app can be in the background before it locks.
    public private(set) var delay: AppLockDelay
    /// Whether the user is authenticating to change a setting, or the App Lock Password is being changed.
    public private(set) var isChangingSettings = false
    /// Whether the App Lock Password is set, so unlocking asks for it after device authentication.
    public private(set) var isPasswordSet: Bool
    /// Whether too many wrong App Lock Passwords in a row erase every vault. Off unless the user turns it on.
    public private(set) var erasesAfterFailedPasswords: Bool

    private let settings: AppLockSettingsStore
    private let authenticationService: DeviceAuthenticationService
    private let passwordService: (any AppLockPasswordService)?
    private let clock: any AppLockClock
    private let purgeSensitiveData: @MainActor () -> Void
    private let didChangeSettings: @MainActor () -> Void

    /// Counts locks. An authentication that was underway when the app locked again belongs to the earlier lock,
    /// so its result is thrown away rather than unlocking the new one.
    @ObservationIgnored private var lockGeneration = 0
    /// Whether to start unlocking by itself as soon as the app is active: set on every lock, and spent on the first
    /// try, so a cancelled prompt isn't shown again until the user asks.
    @ObservationIgnored private var startsUnlockWhenActive = false
    @ObservationIgnored private var scenePhase: AppScenePhase?
    /// When the app last went to the background unlocked, while it has yet to come back: what `delay` counts from.
    @ObservationIgnored private var wentToBackgroundAt: ContinuousClock.Instant?
    @ObservationIgnored private var isAuthenticationUnderway = false
    @ObservationIgnored private var actionsAwaitingUnlock = [@MainActor () -> Void]()
    /// The unlock started when the app became active, kept so tests can wait for it.
    @ObservationIgnored private(set) var automaticUnlock: Task<Void, Never>?
    /// Locking the vault as the app last locked, which unlocking waits for, so it can't open the vault only for this
    /// to lock it again.
    @ObservationIgnored private(set) var vaultLock: Task<Void, Never>?
    /// Opening the vault without the app having locked (`openVaultIfUnlocked()`), which actions waiting for the app to
    /// be unlocked wait for too.
    @ObservationIgnored private(set) var vaultOpening: Task<Void, Never>?

    /// - Parameters:
    ///   - passwordService: The App Lock Password's storage, or `nil` where the password isn't offered.
    ///   - delay: How long it can be in the background before it locks, if not the user's setting: the AutoFill
    ///     extension always locks straight away.
    ///   - clock: What `delay`, and the wait after wrong passwords, are measured with.
    ///   - purgeSensitiveData: Clears sensitive data from memory. Called every time the app locks.
    ///   - didChangeSettings: Called when the lock or its password is turned on or off, so the extensions can catch
    ///     up.
    public init(
        settings: AppLockSettingsStore,
        authenticationService: DeviceAuthenticationService,
        passwordService: (any AppLockPasswordService)? = nil,
        delay: AppLockDelay? = nil,
        clock: any AppLockClock = ContinuousClock(),
        purgeSensitiveData: @escaping @MainActor () -> Void,
        didChangeSettings: @escaping @MainActor () -> Void = {},
    ) {
        self.settings = settings
        self.authenticationService = authenticationService
        self.passwordService = passwordService
        self.clock = clock
        self.purgeSensitiveData = purgeSensitiveData
        self.didChangeSettings = didChangeSettings
        let isPasswordSet = passwordService?.isPasswordSet ?? false
        self.isPasswordSet = isPasswordSet
        erasesAfterFailedPasswords = passwordService?.erasesAfterFailedPasswords ?? false
        // A vault with a password can only be opened with it, so the lock is on whatever the setting says.
        let isEnabled = settings.isEnabled || isPasswordSet
        self.isEnabled = isEnabled
        self.delay = delay ?? settings.delay
        // A launch always starts locked, however the app was last left and whatever the delay: the time the app
        // went to the background is only ever kept in memory.
        state = isEnabled ? .locked(AppLockedState(step: .deviceAuthentication)) : .unlocked
        startsUnlockWhenActive = isEnabled
    }

    /// The steps that unlock the app, in order.
    private var unlockSteps: [AppUnlockStep] {
        isPasswordSet ? [.deviceAuthentication, .password] : [.deviceAuthentication]
    }

    public var isLocked: Bool {
        if case .locked = state {
            true
        } else {
            false
        }
    }

    /// Whether the user can turn the lock on: only with a way to authenticate, or they'd be locked out.
    public var canEnable: Bool {
        isEnabled || authenticationService.canAuthenticate
    }

    /// Whether the user can turn the lock off: not while the App Lock Password is set, which needs the lock.
    public var canDisable: Bool {
        !isPasswordSet
    }

    /// Whether the App Lock Password can be set here at all. Not until the encrypted vault's storage is in.
    public var offersPassword: Bool {
        passwordService != nil
    }

    /// How many copies of the vault were set aside because they couldn't be opened, which setting the password
    /// deletes once the user agrees.
    public var setAsideVaultCount: Int {
        passwordService?.setAsideVaultCount ?? 0
    }

    // MARK: - Lifecycle

    /// Tell the lock where the app is in its lifecycle. Locks the app when it goes to the background (or when it
    /// comes back, if it was away for longer than `delay`), and starts unlocking when it comes back locked.
    public func scenePhaseDidChange(to phase: AppScenePhase) {
        scenePhase = phase
        switch phase {
        case .background:
            didEnterBackground()
        case .inactive:
            lockIfAwayTooLong()
        case .active:
            lockIfAwayTooLong()
            startAutomaticUnlockIfNeeded()
        }
    }

    private func didEnterBackground() {
        guard isEnabled else { return }
        if isLocked || delay == .immediately {
            lock()
        } else if wentToBackgroundAt == nil {
            // Only the first report counts: hearing about the same trip to the background again mustn't restart
            // the delay.
            wentToBackgroundAt = clock.now
        }
    }

    /// Locks the app, coming back from the background, if it's been away for at least `delay`.
    private func lockIfAwayTooLong() {
        guard let wentToBackgroundAt else { return }
        self.wentToBackgroundAt = nil
        let timeAway = wentToBackgroundAt.duration(to: clock.now)
        // Time running backwards can't happen with this clock. If it ever did, it's no reason to stay unlocked.
        if timeAway >= delay.duration || timeAway < .zero {
            lock()
        }
    }

    /// Whether a scene in `phase` should hide the vault behind the privacy cover, so the app switcher and anyone
    /// glancing at the screen see nothing of it.
    ///
    /// Only while the lock is on. The app is inactive under the app's own Face ID prompts as well as under Control
    /// Center, so the cover leaves those alone rather than flashing up behind them: the app locks, and is covered,
    /// if it goes to the background from one.
    public func requiresPrivacyCover(in phase: AppScenePhase) -> Bool {
        guard isEnabled else { return false }
        return switch phase {
        case .active: false
        case .inactive: !authenticationService.isAuthenticating
        case .background: true
        }
    }

    private func lock() {
        guard isEnabled else { return }
        wentToBackgroundAt = nil
        lockGeneration += 1
        // An authentication still winding down from before (the system cancels its prompt when the app leaves the
        // foreground) keeps the step underway, so it can't be started twice.
        state = .locked(AppLockedState(step: unlockSteps[0], isInProgress: isAuthenticationUnderway))
        startsUnlockWhenActive = true
        purgeSensitiveData()
        lockVault()
    }

    /// Locks the vault, once any lock of it already underway has finished. It's safe to repeat: locking a locked vault
    /// does nothing.
    private func lockVault() {
        guard let passwordService else { return }
        let previous = vaultLock
        vaultLock = Task {
            await previous?.value
            await passwordService.lockVault()
        }
    }

    /// Locks the app, and the vault with it, as the device locks, whatever the delay, while the App Lock Password is
    /// set: its keys don't stay in memory while the device is locked. The app asks for device authentication and the
    /// password when it next comes back. Without the password, the delay stands.
    public func deviceWillLock() {
        guard isPasswordSet else { return }
        lock()
    }

    private func startAutomaticUnlockIfNeeded() {
        guard startsUnlockWhenActive, scenePhase == .active,
              case let .locked(locked) = state, locked.step.startsAutomatically, !isAuthenticationUnderway
        else { return }
        startsUnlockWhenActive = false
        automaticUnlock = Task { await unlock() }
    }

    // MARK: - Unlocking

    /// Try device authentication, such as asking for Face ID. Unlocks the app if it's the last step.
    ///
    /// When it is, and the vault is encrypted with no password asked for (the password turned off after being on),
    /// it opens the vault too.
    public func unlock() async {
        guard case let .locked(locked) = state, locked.step == .deviceAuthentication else { return }
        await take(locked.step) {
            if let failure = await self.authenticate(reason: "Unlock Vault") {
                return .failed(failure)
            }
            if self.nextStep(after: .deviceAuthentication) == nil, let passwordService = self.passwordService {
                do {
                    try await passwordService.openVaultWithoutPassword()
                } catch {
                    return .failed(.failed)
                }
            }
            return .passed
        }
    }

    /// Try the App Lock Password, once device authentication is passed. Unlocks the app if it's right.
    ///
    /// The password service answers at the same deadline whether it's right, a duress password or wrong, and this
    /// shows its answer as soon as it has it: nothing here takes longer for one than another (MANIFESTO.md C2).
    public func unlock(password: String) async {
        guard case let .locked(locked) = state, locked.step == .password, let passwordService else { return }
        await take(locked.step) {
            do {
                return switch try await passwordService.unlock(password: password) {
                case .accepted: .passed
                case .wrong: .failed(.wrongPassword)
                case let .delayed(remaining): .delayed(remaining)
                case .erased: .erased
                case .onlyAtTheLockScreen: .failed(.needsTheApp)
                }
            } catch {
                return .failed(.failed)
            }
        }
        // Unlocking can find the password was turned off, if the app stopped before it could record that.
        passwordDidChange(in: passwordService)
    }

    private enum StepOutcome {
        case passed
        case failed(AppUnlockFailure)
        /// The password can't be tried yet.
        case delayed(Duration)
        /// Every vault was erased, after too many wrong passwords.
        case erased
    }

    /// Takes a step of unlocking with `attempt`, and moves on to the next step if it's passed.
    private func take(_ step: AppUnlockStep, attempt: () async -> StepOutcome) async {
        guard !isAuthenticationUnderway else { return }
        startsUnlockWhenActive = false
        let generation = lockGeneration
        state = .locked(AppLockedState(step: step, isInProgress: true))
        isAuthenticationUnderway = true
        await vaultLock?.value
        let outcome = await attempt()
        // Whether the password has to wait, found out before the step after device authentication shows, or a wrong
        // password's message does, so neither shows the field ready and then takes it away.
        let passwordRetryAt: ContinuousClock.Instant? = switch outcome {
        case .passed where nextStep(after: step) == .password: await passwordRetryTime()
        case .failed(.wrongPassword): await passwordRetryTime()
        case let .delayed(remaining): clock.now.advanced(by: remaining)
        case .passed, .failed, .erased: nil
        }
        isAuthenticationUnderway = false
        if case .erased = outcome {
            vaultWasErased()
        }

        guard generation == lockGeneration else {
            // The app locked again while this was underway, so the result is stale whatever it is. The new lock
            // stands; start on it if the app's already back in the foreground. After an erase there's no password
            // step any more.
            if case let .locked(current) = state {
                state =
                    .locked(AppLockedState(step: unlockSteps.contains(current.step) ? current.step : unlockSteps[0]))
            }
            // The attempt may have opened the vault after the lock locked it, if the lock got there first. Lock it
            // again, after that.
            lockVault()
            startAutomaticUnlockIfNeeded()
            return
        }

        switch outcome {
        case .passed:
            advance(past: step, passwordRetryAt: passwordRetryAt)
        case let .failed(failure):
            state = .locked(AppLockedState(step: step, failure: failure, passwordRetryAt: passwordRetryAt))
        case .delayed:
            state = .locked(AppLockedState(step: step, passwordRetryAt: passwordRetryAt))
        case .erased:
            // Device authentication is passed, and there's no password any more: the fresh vault opens, like a new
            // install.
            state = .unlocked
        }
    }

    /// Catches up with an erase, even one that finished after the app locked again: there's no password now, and
    /// erasing after failed passwords is off. Nothing waiting to open an item runs: the item was in a vault that's
    /// gone. The app calls it after an erase that didn't start here, such as erasing and starting again when the
    /// vault's data was missing.
    public func vaultWasErased() {
        actionsAwaitingUnlock.removeAll()
        guard let passwordService else { return }
        isPasswordSet = passwordService.isPasswordSet
        erasesAfterFailedPasswords = passwordService.erasesAfterFailedPasswords
        didChangeSettings()
    }

    private func nextStep(after step: AppUnlockStep) -> AppUnlockStep? {
        let steps = unlockSteps
        guard let index = steps.firstIndex(of: step), steps.indices.contains(index + 1) else { return nil }
        return steps[index + 1]
    }

    private func advance(past step: AppUnlockStep, passwordRetryAt: ContinuousClock.Instant?) {
        if let next = nextStep(after: step) {
            state = .locked(AppLockedState(step: next, passwordRetryAt: passwordRetryAt))
        } else {
            state = .unlocked
            let actions = actionsAwaitingUnlock
            actionsAwaitingUnlock.removeAll()
            for action in actions {
                action()
            }
        }
    }

    /// When the password can be tried again, or `nil` if it can be tried now.
    ///
    /// If the wait can't be read, the password service refuses to try the password anyway, so the lock screen offers
    /// it and lets that say so.
    public func passwordRetryTime() async -> ContinuousClock.Instant? {
        guard let passwordService, let remaining = try? await passwordService.remainingDelay(), remaining > .zero
        else { return nil }
        return clock.now.advanced(by: remaining)
    }

    /// Runs `action` now if the app is unlocked, or once the user unlocks it if it isn't.
    ///
    /// For anything that would reveal the vault, such as opening an item from a widget's link.
    ///
    /// While the vault is being opened without the app having locked (`openVaultIfUnlocked()`), it waits for that, so
    /// the action finds the vault open.
    public func performWhenUnlocked(_ action: @escaping @MainActor () -> Void) {
        if isLocked {
            actionsAwaitingUnlock.append(action)
        } else if let vaultOpening {
            Task {
                await vaultOpening.value
                action()
            }
        } else {
            action()
        }
    }

    /// Opens the vault if the app isn't locked: at launch with the lock off, while the password is off after being on.
    /// The vault is encrypted with a key on this device then, and nothing else asks the user to unlock, so it opens
    /// as the plain store always has. Does nothing while the vault is plain.
    public func openVaultIfUnlocked() {
        guard !isLocked, let passwordService else { return }
        vaultOpening = Task {
            try? await passwordService.openVaultWithoutPassword()
            vaultOpening = nil
        }
    }

    // MARK: - Settings

    /// Turn the lock on or off, once the user has authenticated.
    ///
    /// Turning it off needs authentication so that someone else can't open the unlocked app and switch it off.
    /// Turning it on does too, which checks that the user can unlock the app before they're locked out of it. It can't
    /// be turned off while the App Lock Password is set.
    public func setEnabled(_ enabled: Bool) async {
        guard enabled != isEnabled, enabled || canDisable, !isChangingSettings, !isLocked else { return }
        guard await authenticateToChangeSettings(reason: enabled ? "Turn On App Lock" : "Turn Off App Lock") else {
            return
        }
        settings.isEnabled = enabled
        isEnabled = enabled
        wentToBackgroundAt = nil
        didChangeSettings()
    }

    /// Change how long the app can be in the background before it locks.
    ///
    /// A longer delay weakens the lock, so it needs authentication first. A shorter one doesn't.
    public func setDelay(_ newDelay: AppLockDelay) async {
        guard isEnabled, newDelay != delay, !isChangingSettings, !isLocked else { return }
        if newDelay > delay {
            guard await authenticateToChangeSettings(reason: "Lock Vault Less Often") else { return }
        }
        settings.delay = newDelay
        delay = newDelay
    }

    // MARK: - App Lock Password

    /// Sets the App Lock Password, once the user has authenticated, which encrypts the vault with it.
    ///
    /// Authenticating first, as for turning the lock on, means someone else can't open the unlocked app and lock the
    /// user out of their own vault with a password they don't know. The caller has checked the password against
    /// `AppLockPasswordRules` and its confirmation.
    ///
    /// - Parameter deletingSetAsideVaults: Whether the user has agreed to delete the copies of the vault set aside
    ///   (`setAsideVaultCount`), which aren't encrypted.
    /// - Returns: `false` if the user didn't authenticate, and nothing changed.
    /// - Throws: If the password couldn't be set: `VaultEncryptionError` if the vault can't be encrypted as it is.
    ///   Nothing changed then either.
    public func setPassword(_ password: String, deletingSetAsideVaults: Bool = false) async throws -> Bool {
        let passwordService = try passwordServiceForSettings()
        guard !isPasswordSet else { throw AppLockPasswordUnavailableError() }
        guard await authenticateToChangeSettings(reason: "Set App Lock Password") else { return false }
        isChangingSettings = true
        let generation = lockGeneration
        defer {
            isChangingSettings = false
            // Even if it threw: it can have changed how the vault is stored before it did.
            passwordDidChange(in: passwordService)
            // The app locked while the vault was converted. The lock found the plain store, which it doesn't lock, and
            // the conversion then opened the encrypted vault, perhaps after the user had authenticated again: lock the
            // app and the vault now, so the password is asked for.
            if generation != lockGeneration {
                lock()
            }
        }
        try await passwordService.setPassword(password, deletingSetAsideVaults: deletingSetAsideVaults)
        return true
    }

    /// Changes the App Lock Password, if `current` is the password. A wrong one counts as a wrong attempt, just as it
    /// does on the lock screen.
    public func changePassword(current: String, new: String) async throws -> AppLockPasswordResult {
        let passwordService = try passwordServiceForSettings()
        isChangingSettings = true
        defer { isChangingSettings = false }
        return try await passwordService.changePassword(current: current, new: new)
    }

    /// Turns the App Lock Password off, if `current` is the password. A wrong one counts as a wrong attempt, just as
    /// it does on the lock screen. The lock stays on, asking for device authentication only.
    public func turnOffPassword(current: String) async throws -> AppLockPasswordResult {
        let passwordService = try passwordServiceForSettings()
        isChangingSettings = true
        defer {
            isChangingSettings = false
            // Even if it threw: it can have changed how the vault is stored before it did.
            passwordDidChange(in: passwordService)
        }
        return try await passwordService.turnOffPassword(current: current)
    }

    /// Sets a duress password, once the user has authenticated, if `current` is the password: it makes a new, empty
    /// duress vault, which the duress password opens at the lock screen instead of the open vault. Doing it again
    /// replaces that vault.
    ///
    /// Authenticating first, as for setting the password, means someone else can't open the unlocked app and set one
    /// up. It never decides which vault opens: the password does (MANIFESTO.md C4). A wrong current password counts as
    /// a wrong attempt and waits, just as it does on the lock screen. This works the same way in every vault, whether
    /// or not a duress vault was made before, and changes nothing the lock knows about. The caller has checked the
    /// duress password against `AppLockPasswordRules` and its confirmation.
    ///
    /// - Returns: `nil` if the user didn't authenticate, and nothing was tried or changed. Otherwise how the current
    ///   password was taken: `.accepted` once the duress vault is made.
    /// - Throws: `VaultDuressVaultError.matchesAppLockPassword` if the duress password is the current one, or another
    ///   error if the vault couldn't be made. Nothing changed then either.
    public func makeDuressVault(current: String, password: String) async throws -> AppLockPasswordResult? {
        let passwordService = try passwordServiceForSettings()
        guard isPasswordSet else { throw AppLockPasswordUnavailableError() }
        guard await authenticateToChangeSettings(reason: "Set Duress Password") else { return nil }
        isChangingSettings = true
        defer { isChangingSettings = false }
        return try await passwordService.makeDuressVault(current: current, password: password)
    }

    /// Turns erasing after failed passwords on or off, if `current` is the password. A wrong one counts as a wrong
    /// attempt and waits, just as it does on the lock screen, but never erases: the vault is open.
    public func setErasesAfterFailedPasswords(
        _ erases: Bool,
        current: String,
    ) async throws -> AppLockPasswordResult {
        let passwordService = try passwordServiceForSettings()
        isChangingSettings = true
        defer { isChangingSettings = false }
        let result = try await passwordService.setErasesAfterFailedPasswords(erases, current: current)
        erasesAfterFailedPasswords = passwordService.erasesAfterFailedPasswords
        return result
    }

    private func passwordServiceForSettings() throws -> any AppLockPasswordService {
        guard let passwordService, !isLocked, !isChangingSettings else { throw AppLockPasswordUnavailableError() }
        return passwordService
    }

    private func passwordDidChange(in passwordService: any AppLockPasswordService) {
        erasesAfterFailedPasswords = passwordService.erasesAfterFailedPasswords
        guard passwordService.isPasswordSet != isPasswordSet else { return }
        isPasswordSet = passwordService.isPasswordSet
        if isPasswordSet, !isEnabled {
            settings.isEnabled = true
            isEnabled = true
        }
        didChangeSettings()
    }

    // MARK: - Authentication

    /// Asks the user to authenticate before a setting changes. `false` if they didn't, or if the app locked while
    /// the prompt was up.
    private func authenticateToChangeSettings(reason: String) async -> Bool {
        isChangingSettings = true
        defer { isChangingSettings = false }
        let generation = lockGeneration
        let failure = await authenticate(reason: reason)
        return failure == nil && generation == lockGeneration
    }

    private func authenticate(reason: String) async -> AppUnlockFailure? {
        do {
            switch try await authenticationService.authenticate(reason: reason) {
            case .success: return nil
            case .failure(.noAuthenticationSetup): return .unavailable
            case .failure(.authenticationFailure): return .failed
            }
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .systemCancel, .appCancel: return .cancelled
            case .passcodeNotSet: return .unavailable
            default: return .failed
            }
        } catch {
            return .failed
        }
    }
}

/// The App Lock Password can't be changed right now: it isn't offered, the app is locked, or it's already changing.
public struct AppLockPasswordUnavailableError: Error, Equatable {}
