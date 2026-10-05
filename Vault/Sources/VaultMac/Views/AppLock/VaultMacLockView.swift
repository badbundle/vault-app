import SwiftUI
import VaultAppIcon
import VaultFeed

/// The Mac's lock screen: the vault door, and a way to unlock Vault.
///
/// Vault asks for Touch ID or the Mac's password by itself as it comes to the front locked; Unlock is for trying again
/// after a cancelled or failed attempt. The App Lock Password comes next. A real password and a duress one open Vault
/// exactly alike: the lock screen only ever learns that the password was accepted, at the same deadline as a wrong one
/// would be refused (MANIFESTO.md C2).
struct VaultMacLockView: View {
    var state: AppLockedState
    var unlock: () async -> Void
    var unlockWithPassword: (String) async -> Void
    /// What the wait after wrong passwords counts down with: the app lock's clock.
    var clock: any AppLockClock = ContinuousClock()

    @State private var password = ""
    @FocusState private var isPasswordFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 20) {
            VaultLockGlyphView(appearance: colorScheme == .dark ? .dark : .light)
                .frame(width: 88, height: 88)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text("Vault Locked")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(message(passwordWait: passwordWait))
                        .foregroundStyle(isShowingProblem ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                        .accessibilityIdentifier(messageIdentifier)
                }
            }
            .multilineTextAlignment(.center)
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                actions(isWaiting: passwordWait != nil)
            }
            .frame(width: 280)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: state, initial: true) {
            // A password typed before Vault locked again is forgotten, so it isn't waiting in the field, ready to be
            // sent, once Touch ID or the Mac's password next passes.
            if state.step != .password {
                password = ""
            }
            if state.step == .password, !state.isInProgress {
                isPasswordFocused = true
            }
        }
    }

    private func actions(isWaiting: Bool) -> some View {
        VStack(spacing: 12) {
            if state.step == .password {
                SecureField("App Lock Password", text: $password)
                    .secretTextInput()
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .focused($isPasswordFocused)
                    .onSubmit(submitPassword)
                    .disabled(isWaiting || state.isInProgress)
                    .accessibilityIdentifier("app-lock.password")
            }
            Button {
                if state.step == .password {
                    submitPassword()
                } else {
                    Task { await unlock() }
                }
            } label: {
                if state.isInProgress {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Unlock")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(state.isInProgress || (state.step == .password && (password.isEmpty || isWaiting)))
            .accessibilityIdentifier("app-lock.unlock")
        }
    }

    private func submitPassword() {
        guard state.step == .password, password.isNotEmpty, !state.isInProgress, passwordWait == nil else { return }
        let entered = password
        Task {
            await unlockWithPassword(entered)
            password = ""
        }
    }

    /// How long the password has to wait, if it does.
    private var passwordWait: Duration? {
        state.step == .password
            ? VaultMacPasswordWait.remaining(until: state.passwordRetryAt, now: clock.now)
            : nil
    }

    private func message(passwordWait: Duration?) -> String {
        let tryAgainLater = passwordWait.map(VaultMacPasswordWait.tryAgainMessage(after:))
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
            return "Set a login password for this Mac to unlock Vault."
        case .wrongPassword:
            return "Wrong password. " + (tryAgainLater ?? "Try again.")
        case .needsTheApp:
            // Only AutoFill says this.
            return "Open Vault to enter your App Lock Password."
        }
    }

    /// Names the message by the problem it shows, if any, for the UI tests.
    private var messageIdentifier: String {
        switch state.failure {
        case .none, .cancelled: "app-lock.message"
        case .failed: "app-lock.message.failed"
        case .unavailable: "app-lock.message.unavailable"
        case .wrongPassword: "app-lock.message.wrong-password"
        case .needsTheApp: "app-lock.message.needs-the-app"
        }
    }

    private var isShowingProblem: Bool {
        switch state.failure {
        case .failed, .unavailable, .wrongPassword: true
        case .none, .cancelled, .needsTheApp: false
        }
    }
}

/// How the Mac's password screens talk about the wait after wrong passwords: only ever how long, never how many
/// attempts have been made or are left. The same as the iOS app's.
enum VaultMacPasswordWait {
    /// How long is left to wait at `now`, or `nil` if the password can be tried.
    static func remaining(until retryAt: ContinuousClock.Instant?, now: ContinuousClock.Instant) -> Duration? {
        guard let retryAt, now < retryAt else { return nil }
        return now.duration(to: retryAt)
    }

    /// "Try again in 5 minutes": in whole minutes rounded up, or hours from an hour.
    static func tryAgainMessage(after remaining: Duration) -> String {
        let minutes = (Double(remaining.components.seconds) / 60).rounded(.up)
        let wait: String = if minutes >= 60 {
            Duration.seconds((minutes / 60).rounded(.up) * 3600).formatted(.units(allowed: [.hours], width: .wide))
        } else {
            Duration.seconds(max(minutes, 1) * 60).formatted(.units(allowed: [.minutes], width: .wide))
        }
        return "Try again in \(wait)."
    }
}
