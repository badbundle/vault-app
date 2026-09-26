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
/// vault's storage is in. It's set, changed and turned off here too, so the lock always knows whether to ask for it.
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

    /// - Parameters:
    ///   - passwordService: The App Lock Password's storage, or `nil` where the password isn't offered.
    ///   - clock: What `delay`, and the wait after wrong passwords, are measured with.
    ///   - purgeSensitiveData: Clears sensitive data from memory. Called every time the app locks.
    ///   - didChangeSettings: Called when the lock or its password is turned on or off, so the extensions can catch
    ///     up.
    public init(
        settings: AppLockSettingsStore,
        authenticationService: DeviceAuthenticationService,
        passwordService: (any AppLockPasswordService)? = nil,
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
        // A vault with a password can only be opened with it, so the lock is on whatever the setting says.
        let isEnabled = settings.isEnabled || isPasswordSet
        self.isEnabled = isEnabled
        delay = settings.delay
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
    public func unlock() async {
        guard case let .locked(locked) = state, locked.step == .deviceAuthentication else { return }
        await take(locked.step) {
            if let failure = await self.authenticate(reason: "Unlock Vault") {
                .failed(failure)
            } else {
                .passed
            }
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
                }
            } catch {
                return .failed(.failed)
            }
        }
    }

    private enum StepOutcome {
        case passed
        case failed(AppUnlockFailure)
        /// The password can't be tried yet.
        case delayed(Duration)
    }

    /// Takes a step of unlocking with `attempt`, and moves on to the next step if it's passed.
    private func take(_ step: AppUnlockStep, attempt: () async -> StepOutcome) async {
        guard !isAuthenticationUnderway else { return }
        startsUnlockWhenActive = false
        let generation = lockGeneration
        state = .locked(AppLockedState(step: step, isInProgress: true))
        isAuthenticationUnderway = true
        let outcome = await attempt()
        // Whether the password has to wait, found out before the step after device authentication shows, or a wrong
        // password's message does, so neither shows the field ready and then takes it away.
        let passwordRetryAt: ContinuousClock.Instant? = switch outcome {
        case .passed where nextStep(after: step) == .password: await passwordRetryTime()
        case .failed(.wrongPassword): await passwordRetryTime()
        case let .delayed(remaining): clock.now.advanced(by: remaining)
        case .passed, .failed: nil
        }
        isAuthenticationUnderway = false

        guard generation == lockGeneration else {
            // The app locked again while this was underway, so the result is stale whatever it is. The new lock
            // stands; start on it if the app's already back in the foreground.
            if case let .locked(current) = state {
                state = .locked(AppLockedState(step: current.step))
            }
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
        }
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
    public func performWhenUnlocked(_ action: @escaping @MainActor () -> Void) {
        if isLocked {
            actionsAwaitingUnlock.append(action)
        } else {
            action()
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
    /// - Returns: `false` if the user didn't authenticate, and nothing changed.
    /// - Throws: If the password couldn't be set. Nothing changed then either.
    public func setPassword(_ password: String) async throws -> Bool {
        let passwordService = try passwordServiceForSettings()
        guard !isPasswordSet else { throw AppLockPasswordUnavailableError() }
        guard await authenticateToChangeSettings(reason: "Set App Lock Password") else { return false }
        isChangingSettings = true
        defer { isChangingSettings = false }
        try await passwordService.setPassword(password)
        passwordDidChange(in: passwordService)
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
        defer { isChangingSettings = false }
        let result = try await passwordService.turnOffPassword(current: current)
        passwordDidChange(in: passwordService)
        return result
    }

    private func passwordServiceForSettings() throws -> any AppLockPasswordService {
        guard let passwordService, !isLocked, !isChangingSettings else { throw AppLockPasswordUnavailableError() }
        return passwordService
    }

    private func passwordDidChange(in passwordService: any AppLockPasswordService) {
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
