import Foundation
import SwiftUI
import VaultAppIcon
import VaultFeed

/// The lock screen: the vault door, and a way to unlock the app.
///
/// The app asks for Face ID by itself when it comes to the foreground locked; the Unlock button is for trying again
/// after a cancelled or failed attempt. Once the app is unlocked, `isOpening` has the door spin open, and the vault
/// comes in on the click.
struct AppLockView: View {
    var state: AppLockedState
    /// Plays the door opening: the app has just been unlocked.
    var isOpening = false
    /// Called when the door's mechanism seats while opening: the moment to show the vault.
    var onOpened: () -> Void = {}
    var unlock: () async -> Void

    @State private var clickCount = 0

    var body: some View {
        AppLockBackdrop(
            doorTransition: isOpening ? .unlock : nil,
            onDoorClick: doorDidClick,
            details: { details },
            action: {
                unlockButton
                    .frame(maxWidth: 440)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            },
        )
        .sensoryFeedback(.impact(weight: .heavy), trigger: clickCount)
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
            Text(message)
                .font(.body)
                .foregroundStyle(isShowingProblem ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                .contentTransition(.opacity)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
        .accessibilityElement(children: .combine)
        .animation(.snappy, value: state.failure)
    }

    private var unlockButton: some View {
        Button {
            Task { await unlock() }
        } label: {
            ProminentActionLabel("Unlock", systemImage: "lock.open.fill", isLoading: state.isInProgress)
        }
        .prominentActionButton()
        .buttonBorderShape(.capsule)
        // Stays in its colors while busy, for the spinner to show up on: `unlock` ignores a second tap anyway.
        .allowsHitTesting(!isBusy)
        .accessibilityLabel(state.isInProgress ? "Unlocking" : "Unlock")
    }

    private var isBusy: Bool {
        state.isInProgress || isOpening
    }

    private var message: String {
        switch state.failure {
        case .none, .cancelled:
            "Unlock to see your codes and notes."
        case .failed:
            "Vault couldn't confirm it's you. Try again."
        case .unavailable:
            "Set up a passcode on this device to unlock Vault."
        }
    }

    private var isShowingProblem: Bool {
        switch state.failure {
        case .failed, .unavailable: true
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
                AppLockView(state: locked) {
                    await appLock.unlock()
                }
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

#Preview("Privacy cover") {
    AppPrivacyCoverView()
}
