import Foundation
import SwiftUI
import VaultAppIcon
import VaultFeed

/// The lock screen: the vault door, and a way to unlock the app.
///
/// The app asks for Face ID by itself when it comes to the foreground locked; the Unlock button is for trying again
/// after a cancelled or failed attempt. When the App Lock Password is set, a password field comes next. Once the app
/// is unlocked, `isOpening` has the door spin open, and the vault comes in on the click.
///
/// A real password and a duress one open the door exactly alike: the lock screen only ever learns that the password
/// was accepted, at the same deadline as a wrong one would be refused (MANIFESTO.md C2).
struct AppLockView: View {
    var state: AppLockedState
    /// Plays the door opening: the app has just been unlocked.
    var isOpening = false
    /// Called when the door's mechanism seats while opening: the moment to show the vault.
    var onOpened: () -> Void = {}
    var unlock: () async -> Void
    var unlockWithPassword: (String) async -> Void = { _ in }

    @State private var clickCount = 0
    @State private var password = ""
    @State private var wrongPasswordCount = 0
    @FocusState private var isPasswordFocused: Bool

    var body: some View {
        AppLockBackdrop(
            doorTransition: isOpening ? .unlock : nil,
            onDoorClick: doorDidClick,
            details: { details },
            action: {
                // Ticks while the password has to wait, so the wait counts down and ends on time.
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    actions(passwordWait: passwordWait)
                        .onChange(of: passwordWait == nil) { _, canTry in
                            if canTry, state.step == .password, !isBusy {
                                isPasswordFocused = true
                            }
                        }
                }
                .frame(maxWidth: 440)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            },
        )
        .sensoryFeedback(.impact(weight: .heavy), trigger: clickCount)
        .onChange(of: state, initial: true) {
            // Ready for the password as soon as it can be typed: when the step starts, and again after each try,
            // which took the focus away while it was checked.
            if state.step == .password, !isBusy, passwordWait == nil {
                isPasswordFocused = true
            }
        }
        .onChange(of: state.failure) { _, failure in
            if failure == .wrongPassword {
                wrongPasswordCount += 1
                // Focus stays in the field, so VoiceOver wouldn't hear the message change otherwise.
                AccessibilityNotification.Announcement(message(passwordWait: passwordWait)).post()
            }
        }
        .onChange(of: isOpening) { _, isOpening in
            if isOpening {
                password = ""
                isPasswordFocused = false
            }
        }
    }

    private func doorDidClick() {
        clickCount += 1
        onOpened()
    }

    private var details: some View {
        VStack(spacing: 12) {
            Text("Vault Locked")
                .font(.title2.bold())
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(message(passwordWait: passwordWait))
                    .font(.body)
                    .foregroundStyle(isShowingProblem ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .contentTransition(.opacity)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
        .accessibilityElement(children: .combine)
        .animation(.snappy, value: state.failure)
    }

    private func actions(passwordWait: Duration?) -> some View {
        VStack(spacing: 12) {
            if state.step == .password {
                passwordField(isWaiting: passwordWait != nil)
            }
            unlockButton(isWaiting: passwordWait != nil)
        }
    }

    private func passwordField(isWaiting: Bool) -> some View {
        SecureField("App Lock Password", text: $password)
            .secretTextInput(.verbatim)
            // SwiftUI doesn't give VoiceOver a secure field's own label.
            .accessibilityLabel("App Lock Password")
            .focused($isPasswordFocused)
            .submitLabel(.go)
            .onSubmit(submitPassword)
            .padding(.horizontal, 20)
            .frame(minHeight: 52)
            .glassEffect(.regular.interactive(), in: .capsule)
            .glassSnapshotBackdrop(in: .capsule)
            .disabled(isWaiting || isBusy)
            .wrongPasswordFeedback(trigger: wrongPasswordCount)
            // The lock screen is in a window of its own, which has to be key for the field to take the keyboard.
            .makesWindowKey(!isOpening)
    }

    private func unlockButton(isWaiting: Bool) -> some View {
        Button {
            if state.step == .password {
                submitPassword()
            } else {
                Task { await unlock() }
            }
        } label: {
            ProminentActionLabel("Unlock", systemImage: "lock.open.fill", isLoading: state.isInProgress)
        }
        .prominentActionButton()
        .buttonBorderShape(.capsule)
        .disabled(state.step == .password && !isBusy && (password.isEmpty || isWaiting))
        // Stays in its colors while busy, for the spinner to show up on: `unlock` ignores a second tap anyway.
        .allowsHitTesting(!isBusy)
        .accessibilityLabel(state.isInProgress ? "Unlocking" : "Unlock")
    }

    private func submitPassword() {
        guard state.step == .password, password.isNotEmpty, !isBusy, passwordWait == nil else { return }
        let entered = password
        Task {
            await unlockWithPassword(entered)
            password = ""
        }
    }

    private var isBusy: Bool {
        state.isInProgress || isOpening
    }

    /// How long the password has to wait, if it does.
    private var passwordWait: Duration? {
        state.step == .password ? AppLockPasswordWait.remaining(until: state.passwordRetryAt) : nil
    }

    private func message(passwordWait: Duration?) -> String {
        let tryAgainLater = passwordWait.map(AppLockPasswordWait.tryAgainMessage(after:))
        switch state.failure {
        case .none, .cancelled:
            return switch state.step {
            case .deviceAuthentication: "Unlock to see your codes and notes."
            case .password: tryAgainLater ?? "Enter your App Lock Password."
            }
        case .failed:
            return switch state.step {
            case .deviceAuthentication: "Vault couldn't confirm it's you. Try again."
            case .password: "Vault couldn't check the password. Try again."
            }
        case .unavailable:
            return "Set up a passcode on this device to unlock Vault."
        case .wrongPassword:
            return "Wrong password. " + (tryAgainLater ?? "Try again.")
        }
    }

    private var isShowingProblem: Bool {
        switch state.failure {
        case .failed, .unavailable, .wrongPassword: true
        case .none, .cancelled: false
        }
    }
}

/// Covers the vault while the app is out of the foreground with the app lock on, so the app switcher shows nothing
/// of it: the lock screen's door, without the lock screen.
struct AppPrivacyCoverView: View {
    var body: some View {
        AppLockBackdrop()
    }
}

/// Covers the vault while the screen is recorded, mirrored or shared, so it doesn't show up in the recording or on the
/// other screen: the lock screen's door, and why the vault has gone.
struct AppScreenCaptureCoverView: View {
    var body: some View {
        AppLockBackdrop(
            details: {
                VStack(spacing: 12) {
                    Text("Vault Hidden")
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                        .accessibilityAddTraits(.isHeader)
                    Text("Your screen is being recorded or shared. Vault will reappear when that stops.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .accessibilityElement(children: .combine)
            },
            action: { EmptyView() },
        )
    }
}

/// Sends the user to Vault, where the AutoFill extension can't unlock the vault itself: it hasn't the memory to
/// derive the App Lock Password's key. The app always can.
public struct AppLockOpenVaultView: View {
    var cancel: () -> Void

    public init(cancel: @escaping () -> Void) {
        self.cancel = cancel
    }

    public var body: some View {
        AppLockBackdrop(
            details: {
                VStack(spacing: 12) {
                    Text("Open Vault")
                        .font(.title2.bold())
                        .foregroundStyle(.primary)
                        .accessibilityAddTraits(.isHeader)
                    Text(
                        "AutoFill doesn't have enough memory to unlock your vault right now. Open Vault to copy your code instead.",
                    )
                    .font(.body)
                    .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .accessibilityElement(children: .combine)
            },
            action: { EmptyView() },
        )
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: cancel)
                    .tint(.red)
            }
        }
    }
}

/// Shows `content` only once the user has unlocked the app, with the lock screen until then.
///
/// For the AutoFill extension, which has its own copy of the lock: its prompt comes up as soon as the extension
/// does, and `cancel` gives up on the request instead.
public struct AppLockGate<Content: View>: View {
    var appLock: AppLockService
    var cancel: () -> Void
    @ViewBuilder var content: () -> Content

    @Environment(\.scenePhase) private var scenePhase

    public init(appLock: AppLockService, cancel: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.appLock = appLock
        self.cancel = cancel
        self.content = content
    }

    public var body: some View {
        ZStack {
            if case let .locked(locked) = appLock.state {
                AppLockView(
                    state: locked,
                    unlock: { await appLock.unlock() },
                    unlockWithPassword: { await appLock.unlock(password: $0) },
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: cancel)
                            .tint(.red)
                    }
                }
            } else {
                content()
            }
        }
        .animation(.easeOut(duration: 0.3), value: appLock.isLocked)
        .onChange(of: scenePhase, initial: true) { _, phase in
            appLock.scenePhaseDidChange(to: AppScenePhase(phase))
        }
    }
}

#Preview("Locked") {
    AppLockView(state: .init(step: .deviceAuthentication)) {}
}

#Preview("Failed") {
    AppLockView(state: .init(step: .deviceAuthentication, failure: .failed)) {}
}

#Preview("Password") {
    AppLockView(state: .init(step: .password)) {}
}

#Preview("Wrong password, waiting") {
    AppLockView(state: .init(
        step: .password,
        failure: .wrongPassword,
        passwordRetryAt: .now.advanced(by: .seconds(5 * 60)),
    )) {}
}

#Preview("Privacy cover") {
    AppPrivacyCoverView()
}

#Preview("Screen capture cover") {
    AppScreenCaptureCoverView()
}

#Preview("AutoFill, open Vault") {
    NavigationStack {
        AppLockOpenVaultView {}
    }
}
