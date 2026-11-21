import SwiftUI

/// A backup's seal on screen, on iOS and the Mac: the same picture as on its PDF (`BackupSealArtwork`).
///
/// It's decorative, so VoiceOver skips it: the screen it's on says the seal's code in words.
public struct BackupSealView: View {
    var seal: BackupSeal
    var stampsOnAppear: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    /// - Parameter stampsOnAppear: Lifts the seal and presses it down once when it first appears, as a seal is
    ///   stamped, to mark a backup saved or checked. Not with Reduce Motion.
    public init(seal: BackupSeal, stampsOnAppear: Bool = false) {
        self.seal = seal
        self.stampsOnAppear = stampsOnAppear
    }

    public var body: some View {
        Canvas { context, size in
            context.withCGContext { cgContext in
                BackupSealArtwork(seal: seal).draw(in: cgContext, rect: CGRect(origin: .zero, size: size))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        // The press starts and ends at rest, so the seal is always drawn where it ends up: before it's stamped, if it
        // never is, and in the first frame, which is all a snapshot sees.
        .keyframeAnimator(initialValue: Stamp.rest, trigger: hasAppeared) { content, stamp in
            content
                .scaleEffect(stamp.scale)
                .rotationEffect(.degrees(stamp.rotation))
        } keyframes: { _ in
            KeyframeTrack(\.scale) {
                CubicKeyframe(1.12, duration: 0.15)
                CubicKeyframe(0.93, duration: 0.1)
                SpringKeyframe(1, duration: 0.4, spring: .bouncy(duration: 0.4, extraBounce: 0.15))
            }
            KeyframeTrack(\.rotation) {
                CubicKeyframe(-6, duration: 0.15)
                CubicKeyframe(0, duration: 0.1)
            }
        }
        .onAppear {
            if stampsOnAppear, !reduceMotion {
                hasAppeared = true
            }
        }
        .accessibilityHidden(true)
    }

    private struct Stamp {
        var scale: Double
        var rotation: Double

        static let rest = Stamp(scale: 1, rotation: 0)
    }
}

#Preview {
    let seals = (0 ..< 3).map { index in
        BackupSeal(digest: (0 ..< 32).map { byte -> UInt8 in UInt8((byte * 37 + index * 91) % 256) })
    }
    HStack(spacing: 24) {
        ForEach(seals, id: \.self) { seal in
            BackupSealView(seal: seal)
                .frame(width: 96)
        }
    }
    .padding()
}
