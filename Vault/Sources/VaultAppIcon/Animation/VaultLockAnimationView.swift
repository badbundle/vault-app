import SwiftUI

/// Plays one run of the vault door's mechanism.
///
/// Lock: the door swings shut and lands with a thunk, the wheel winds up a touch,
/// then spins round and seats on a spring so it overshoots and settles. Unlock: the
/// wheel spins back the other way and the door pops open a crack, bouncing on its
/// hinge. Decrypt: the wheel works a combination and the door swings wide.
/// Decryption failed: the wheel catches and the door rattles, still shut. With
/// Reduce Motion on, the glyph is shown static in its final state and only the
/// callbacks happen, sooner.
public struct VaultLockAnimationView: View {
    public var transition: VaultLockTransition
    public var palette: VaultAppIconPalette
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
        self.init(
            transition: transition,
            palette: appearance.palette,
            metrics: metrics,
            onClick: onClick,
            onFinished: onFinished,
        )
    }

    /// Drawn in colors of its own rather than one of the icon's appearances: see
    /// `VaultLockGlyphView`.
    public init(
        transition: VaultLockTransition,
        palette: VaultAppIconPalette,
        metrics: VaultIconMetrics = .standard,
        onClick: @escaping () -> Void = {},
        onFinished: @escaping () -> Void = {},
    ) {
        self.transition = transition
        self.palette = palette
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
                    animator(keyframes: LockGlyphKeyframes.lock)
                case .unlock:
                    animator(keyframes: LockGlyphKeyframes.unlock)
                case .decrypt:
                    animator(keyframes: LockGlyphKeyframes.decrypt)
                case .decryptionFailed:
                    animator(keyframes: LockGlyphKeyframes.decryptionFailed)
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

    /// One straight-line set of keyframes per transition rather than one with
    /// conditions inside the keyframes builder: simpler to read, and each run
    /// starts from its own initial value.
    private func animator(keyframes: some Keyframes<LockGlyphKeyframes>) -> some View {
        KeyframeAnimator(initialValue: LockGlyphKeyframes.initial(for: transition), trigger: isPlaying) { values in
            glyph(values)
        } keyframes: { _ in
            keyframes
        }
    }

    private func glyph(_ values: LockGlyphKeyframes) -> some View {
        let shake = values.doorShake
        return VaultLockGlyphView(
            wheelRotation: .degrees(values.wheelRotation),
            doorOpening: values.doorOpening,
            palette: palette,
            metrics: metrics,
        )
        .scaleEffect(values.doorScale)
        .visualEffect { content, proxy in
            content.offset(x: shake * proxy.size.width)
        }
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

// MARK: - Keyframes

/// Out here rather than inside each animator so tests can play them through a
/// `KeyframeTimeline` and hold them to `VaultLockChoreography`'s timings.
extension LockGlyphKeyframes {
    @KeyframesBuilder<LockGlyphKeyframes>
    static var lock: some Keyframes<LockGlyphKeyframes> {
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

    @KeyframesBuilder<LockGlyphKeyframes>
    static var unlock: some Keyframes<LockGlyphKeyframes> {
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

    @KeyframesBuilder<LockGlyphKeyframes>
    static var decrypt: some Keyframes<LockGlyphKeyframes> {
        // The wheel works the combination: a turn one way, back the other, then
        // round to seat with a bounce…
        KeyframeTrack(\.wheelRotation) {
            SpringKeyframe(120, duration: 0.2, spring: Spring(duration: 0.2, bounce: 0.15))
            SpringKeyframe(-45, duration: 0.24, spring: Spring(duration: 0.22, bounce: 0.15))
            SpringKeyframe(270, duration: 0.7, spring: Spring(duration: 0.45, bounce: 0.35))
        }
        // …the door gives as the bolts release…
        KeyframeTrack(\.doorScale) {
            LinearKeyframe(1, duration: 0.66)
            CubicKeyframe(1.05, duration: 0.08)
            SpringKeyframe(1, duration: 0.4, spring: .bouncy)
        }
        // …and swings wide open on its hinge.
        KeyframeTrack(\.doorOpening) {
            LinearKeyframe(0, duration: 0.68)
            SpringKeyframe(
                VaultLockChoreography.decryptedDoor,
                duration: 0.56,
                spring: Spring(duration: 0.5, bounce: 0.25),
            )
        }
    }

    @KeyframesBuilder<LockGlyphKeyframes>
    static var decryptionFailed: some Keyframes<LockGlyphKeyframes> {
        // The wheel tries to turn and catches against the bolts, jolting back…
        KeyframeTrack(\.wheelRotation) {
            CubicKeyframe(18, duration: 0.06)
            CubicKeyframe(-14, duration: 0.08)
            CubicKeyframe(8, duration: 0.08)
            CubicKeyframe(-3, duration: 0.07)
            SpringKeyframe(0, duration: 0.24, spring: .snappy)
        }
        // …and the door rattles in its frame.
        KeyframeTrack(\.doorShake) {
            CubicKeyframe(0.1, duration: 0.06)
            CubicKeyframe(-0.08, duration: 0.08)
            CubicKeyframe(0.05, duration: 0.08)
            CubicKeyframe(-0.02, duration: 0.07)
            SpringKeyframe(0, duration: 0.24, spring: .snappy)
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

#Preview("Decrypt") {
    VaultLockAnimationView(transition: .decrypt)
        .frame(width: 300, height: 300)
        .padding()
        .background(Color.black)
}

#Preview("Decryption failed") {
    VaultLockAnimationView(transition: .decryptionFailed)
        .frame(width: 300, height: 300)
        .padding()
        .background(Color.black)
}
