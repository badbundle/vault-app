import SwiftUI

/// Plays one lock or unlock of the vault door.
///
/// Lock: the door swings shut and lands with a thunk, the wheel winds up a touch,
/// then spins round and seats on a spring so it overshoots and settles. Unlock: the
/// wheel spins back the other way and the door pops open a crack, bouncing on its
/// hinge. With Reduce Motion on, the glyph is shown static in its final state and
/// only the callbacks happen, sooner.
public struct VaultLockAnimationView: View {
    public var transition: VaultLockTransition
    public var appearance: VaultAppIconAppearance
    public var metrics: VaultIconMetrics
    /// Called when the mechanism seats: the moment for a haptic.
    public var onClick: () -> Void
    /// Called once the animation has settled.
    public var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPlaying = false

    public init(
        transition: VaultLockTransition,
        appearance: VaultAppIconAppearance = .dark,
        metrics: VaultIconMetrics = .standard,
        onClick: @escaping () -> Void = {},
        onFinished: @escaping () -> Void = {},
    ) {
        self.transition = transition
        self.appearance = appearance
        self.metrics = metrics
        self.onClick = onClick
        self.onFinished = onFinished
    }

    public var body: some View {
        Group {
            if reduceMotion {
                glyph(LockGlyphKeyframes.final(for: transition))
            } else {
                switch transition {
                case .lock:
                    lockAnimator
                case .unlock:
                    unlockAnimator
                }
            }
        }
        .onAppear {
            isPlaying = true
        }
        .task {
            await runTimeline()
        }
    }

    /// Lock and unlock are two straight-line animators rather than one with
    /// conditions inside the keyframes builder: simpler to read, and each run
    /// starts from its own initial value.
    private var lockAnimator: some View {
        KeyframeAnimator(initialValue: LockGlyphKeyframes.initial(for: .lock), trigger: isPlaying) { values in
            glyph(values)
        } keyframes: { _ in
            // The door swings shut first…
            KeyframeTrack(\.doorOpening) {
                LinearKeyframe(VaultLockChoreography.openedDoor, duration: 0.06)
                CubicKeyframe(0, duration: 0.22)
            }
            // …lands with a thunk…
            KeyframeTrack(\.doorScale) {
                LinearKeyframe(1, duration: 0.28)
                CubicKeyframe(0.965, duration: 0.06)
                SpringKeyframe(1, duration: 0.4, spring: .bouncy)
            }
            // …then the wheel winds up, spins round and seats with a bounce.
            KeyframeTrack(\.wheelRotation) {
                LinearKeyframe(0, duration: 0.30)
                CubicKeyframe(-20, duration: 0.12)
                SpringKeyframe(450, duration: 0.78, spring: Spring(duration: 0.6, bounce: 0.38))
            }
        }
    }

    private var unlockAnimator: some View {
        KeyframeAnimator(initialValue: LockGlyphKeyframes.initial(for: .unlock), trigger: isPlaying) { values in
            glyph(values)
        } keyframes: { _ in
            // The wheel spins back the other way…
            KeyframeTrack(\.wheelRotation) {
                CubicKeyframe(20, duration: 0.10)
                SpringKeyframe(-450, duration: 0.72, spring: Spring(duration: 0.6, bounce: 0.3))
            }
            // …the door gives a little as the bolts release…
            KeyframeTrack(\.doorScale) {
                LinearKeyframe(1, duration: 0.62)
                CubicKeyframe(1.03, duration: 0.08)
                SpringKeyframe(1, duration: 0.4, spring: .bouncy)
            }
            // …and pops open a crack, bouncing on its hinge.
            KeyframeTrack(\.doorOpening) {
                LinearKeyframe(0, duration: 0.62)
                SpringKeyframe(
                    VaultLockChoreography.openedDoor,
                    duration: 0.55,
                    spring: Spring(duration: 0.45, bounce: 0.45),
                )
            }
        }
    }

    private func glyph(_ values: LockGlyphKeyframes) -> some View {
        VaultLockGlyphView(
            wheelRotation: .degrees(values.wheelRotation),
            doorOpening: values.doorOpening,
            appearance: appearance,
            metrics: metrics,
        )
        .scaleEffect(values.doorScale)
    }

    /// Reports the click and the end of the run. The longest keyframe track is
    /// shorter than `totalDuration`, so `onFinished` arrives after the spring has
    /// settled. Cancellation means the view went away early: nothing to report.
    private func runTimeline() async {
        let choreography = VaultLockChoreography(transition: transition, reduceMotion: reduceMotion)
        do {
            try await Task.sleep(for: choreography.clickDelay)
            onClick()
            try await Task.sleep(for: choreography.totalDuration - choreography.clickDelay)
            onFinished()
        } catch {
            // Cancelled: see above.
        }
    }
}

#Preview("Lock") {
    VaultLockAnimationView(transition: .lock)
        .frame(width: 300, height: 300)
        .padding()
        .background(Color.black)
}

#Preview("Unlock") {
    VaultLockAnimationView(transition: .unlock)
        .frame(width: 300, height: 300)
        .padding()
        .background(Color.black)
}
