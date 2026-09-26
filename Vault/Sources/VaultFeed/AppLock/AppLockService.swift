import Foundation
import LocalAuthentication

/// The app lock: when it's on, the whole app stays behind a lock screen until the user authenticates.
///
/// The app starts locked and locks again whenever it goes to the background. Going inactive (Control Center, the
/// app switcher) doesn't lock the app, but the scene covers the vault with a privacy cover (see
/// `requiresPrivacyCover(in:)`) so it doesn't show in the app switcher.
///
/// Unlocking takes the user through `AppUnlockStep`s in order. Device authentication is the only one for now, and
/// it's asked for automatically when the app comes to the foreground locked; a cancelled or failed try waits for the
/// user to try again with `unlock()`.
///
/// Anything that would reveal the vault while it's locked, such as opening an item from a widget, waits in
/// `performWhenUnlocked(_:)` until the user has unlocked the app.
@MainActor
@Observable
public final class AppLockService {
    public private(set) var state: AppLockState
    /// Whether the app lock is on.
    public private(set) var isEnabled: Bool
    /// Whether the user is authenticating to turn the lock on or off.
    public private(set) var isChangingEnabled = false

    private let settings: AppLockSettingsStore
    private let authenticationService: DeviceAuthenticationService
    private let purgeSensitiveData: @MainActor () -> Void
    private let didChangeSettings: @MainActor () -> Void

    /// Counts locks. An authentication that was underway when the app locked again belongs to the earlier lock,
    /// so its result is thrown away rather than unlocking the new one.
    @ObservationIgnored private var lockGeneration = 0
    /// Whether to start unlocking by itself as soon as the app is active: set on every lock, and spent on the first
    /// try, so a cancelled prompt isn't shown again until the user asks.
    @ObservationIgnored private var startsUnlockWhenActive = false
    @ObservationIgnored private var scenePhase: AppScenePhase?
    @ObservationIgnored private var isAuthenticationUnderway = false
    @ObservationIgnored private var actionsAwaitingUnlock = [@MainActor () -> Void]()
    /// The unlock started when the app became active, kept so tests can wait for it.
    @ObservationIgnored private(set) var automaticUnlock: Task<Void, Never>?

    /// - Parameters:
    ///   - purgeSensitiveData: Clears sensitive data from memory. Called every time the app locks.
    ///   - didChangeSettings: Called when the lock is turned on or off, so the extensions can catch up.
    public init(
        settings: AppLockSettingsStore,
        authenticationService: DeviceAuthenticationService,
        purgeSensitiveData: @escaping @MainActor () -> Void,
        didChangeSettings: @escaping @MainActor () -> Void = {},
    ) {
        self.settings = settings
        self.authenticationService = authenticationService
        self.purgeSensitiveData = purgeSensitiveData
        self.didChangeSettings = didChangeSettings
        let isEnabled = settings.isEnabled
        self.isEnabled = isEnabled
        // A launch always starts locked, however the app was last left.
        state = isEnabled ? .locked(AppLockedState(step: Self.unlockSteps[0])) : .unlocked
        startsUnlockWhenActive = isEnabled
    }

    /// The steps that unlock the app, in order.
    private static let unlockSteps: [AppUnlockStep] = [.deviceAuthentication]

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

    // MARK: - Lifecycle

    /// Tell the lock where the app is in its lifecycle. Locks the app when it goes to the background, and starts
    /// unlocking when it comes back to the foreground locked.
    public func scenePhaseDidChange(to phase: AppScenePhase) {
        scenePhase = phase
        switch phase {
        case .background:
            lock()
        case .inactive:
            break
        case .active:
            startAutomaticUnlockIfNeeded()
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
        lockGeneration += 1
        // An authentication still winding down from before (the system cancels its prompt when the app leaves the
        // foreground) keeps the step underway, so it can't be started twice.
        state = .locked(AppLockedState(step: Self.unlockSteps[0], isInProgress: isAuthenticationUnderway))
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

    /// Try the current step of unlocking, such as asking for Face ID. Unlocks the app once the last step is passed.
    public func unlock() async {
        guard case let .locked(locked) = state, !isAuthenticationUnderway else { return }
        startsUnlockWhenActive = false
        let generation = lockGeneration
        state = .locked(AppLockedState(step: locked.step, isInProgress: true))
        isAuthenticationUnderway = true
        let failure = await attempt(locked.step)
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

        if let failure {
            state = .locked(AppLockedState(step: locked.step, failure: failure))
        } else {
            advance(past: locked.step)
        }
    }

    private func attempt(_ step: AppUnlockStep) async -> AppUnlockFailure? {
        switch step {
        case .deviceAuthentication:
            await authenticate(reason: "Unlock Vault")
        }
    }

    private func advance(past step: AppUnlockStep) {
        let steps = Self.unlockSteps
        if let index = steps.firstIndex(of: step), steps.indices.contains(index + 1) {
            state = .locked(AppLockedState(step: steps[index + 1]))
        } else {
            state = .unlocked
            let actions = actionsAwaitingUnlock
            actionsAwaitingUnlock.removeAll()
            for action in actions {
                action()
            }
        }
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
    /// Turning it on does too, which checks that the user can unlock the app before they're locked out of it.
    public func setEnabled(_ enabled: Bool) async {
        guard enabled != isEnabled, !isChangingEnabled, !isLocked else { return }
        isChangingEnabled = true
        defer { isChangingEnabled = false }
        let generation = lockGeneration
        let failure = await authenticate(reason: enabled ? "Turn On App Lock" : "Turn Off App Lock")
        // Nothing changes if the app locked while the prompt was up.
        guard failure == nil, generation == lockGeneration else { return }
        settings.isEnabled = enabled
        isEnabled = enabled
        didChangeSettings()
    }

    // MARK: - Authentication

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
