import SwiftUI
import VaultAppIcon

/// The full-screen layer the lock animation plays on.
///
/// Lives in its own window, so it takes the presenter by value rather than from
/// the environment. A tap anywhere skips to the end.
struct LockAnimationOverlayView: View {
    var presenter: LockAnimationPresenter
    @State private var clickCount = 0

    var body: some View {
        ZStack {
            if let playback = presenter.current {
                LockAnimationPlaybackView(
                    transition: playback.transition,
                    onClick: { clickCount += 1 },
                    onFinished: { presenter.finish(playback.id) },
                )
                .id(playback.id)
            }
        }
        .ignoresSafeArea()
        // `SensoryFeedback.impact` is iOS-only, which is why the haptic sits here
        // rather than inside `VaultAppIcon`.
        .sensoryFeedback(.impact(weight: .heavy), trigger: clickCount)
    }
}

private struct LockAnimationPlaybackView: View {
    var transition: VaultLockTransition
    var onClick: () -> Void
    var onFinished: () -> Void

    @State private var isVisible = false
    @State private var isFinishing = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
            VaultLockAnimationView(transition: transition, appearance: .dark, onClick: onClick, onFinished: finish)
                .frame(maxWidth: 380, maxHeight: 380)
                .padding(40)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: finish)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.15)) {
                isVisible = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isImage)
    }

    private var accessibilityLabel: String {
        switch transition {
        case .lock: "Item locked"
        case .unlock: "Item unlocked"
        }
    }

    /// Fades out and then reports back. Idempotent, so a skip tap and the
    /// animation's own end can both call it.
    private func finish() {
        guard !isFinishing else { return }
        isFinishing = true
        withAnimation(.easeIn(duration: 0.2), completionCriteria: .removed) {
            isVisible = false
        } completion: {
            onFinished()
        }
    }
}
