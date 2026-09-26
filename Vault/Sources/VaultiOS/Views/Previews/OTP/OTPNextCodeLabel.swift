import SwiftUI
import VaultFeed
import VaultiOSShared

/// The code after the current one, shown small above a time-based code's timer bar in the last seconds of its
/// countdown.
struct OTPNextCodeLabel: View {
    var code: String
    /// Larger, for the code's own page.
    var isProminent = false

    var body: some View {
        // Colors rather than hierarchical styles, which would take on the tint of the button a code sits in.
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("Next")
                .foregroundStyle(Color.secondary)
                .accessibilityLabel("Next code")
            OTPCodeTextView(codeState: .visible(code), scaledDigitSpacing: 3)
                .fontDesign(.monospaced)
                .fontWeight(.semibold)
                .foregroundStyle(Color.primary.opacity(0.75))
        }
        .font(isProminent ? .subheadline : .caption2)
        .lineLimit(1)
        // Read as one: "Next code, 654, 321".
        .accessibilityElement(children: .combine)
        // A card has only the room its bar leaves, so it stops growing where the bar does.
        .dynamicTypeSize(...CodeStateTimerBarMetrics.largestDynamicTypeSize)
    }
}

extension View {
    /// Shows `nextCode`, when there is one, just above this view (a code's timer bar) at its trailing edge.
    ///
    /// Drawn over the space above the bar rather than given room of its own, so the view doesn't change size, or move
    /// what's around it, as the next code comes and goes.
    func nextCodeAbove(_ nextCode: String?, isProminent: Bool = false) -> some View {
        overlay(alignment: .topTrailing) {
            ZStack {
                if let nextCode {
                    OTPNextCodeLabel(code: nextCode, isProminent: isProminent)
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottomTrailing)))
                }
            }
            .alignmentGuide(.top) { $0[.bottom] + 4 }
            .animation(.snappy, value: nextCode)
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        Capsule()
            .fill(.blue)
            .frame(height: 12)
            .nextCodeAbove("482190")
        Capsule()
            .fill(.blue)
            .frame(height: 12)
            .nextCodeAbove("48219035", isProminent: true)
    }
    .padding()
}
