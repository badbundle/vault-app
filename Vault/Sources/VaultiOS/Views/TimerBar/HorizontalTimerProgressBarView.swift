import Combine
import SwiftUI

struct HorizontalTimerProgressBarView: View {
    var fractionCompleted: Double
    var color: Color
    var backgroundColor: Color = .init(.quaternarySystemFill)

    @Environment(\.redactionReasons) private var redactionReasons

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(backgroundColor)
                Rectangle()
                    .fill(color)
                    .frame(
                        width: isPlaceholder ? 0 : fractionCompleted * proxy.size.width,
                        alignment: .leading,
                    )
            }
        }
    }

    private var isPlaceholder: Bool {
        redactionReasons.contains(.placeholder)
    }
}

#Preview("Example Views", traits: .sizeThatFitsLayout) {
    VStack {
        HorizontalTimerProgressBarView(
            fractionCompleted: 0.0,
            color: .blue,
        )
        .frame(width: 250, height: 20)

        HorizontalTimerProgressBarView(
            fractionCompleted: 0.4,
            color: .blue,
        )
        .frame(width: 250, height: 20)
        .redacted(reason: .placeholder)

        HorizontalTimerProgressBarView(
            fractionCompleted: 0.4,
            color: .blue,
        )
        .frame(width: 250, height: 20)

        HorizontalTimerProgressBarView(
            fractionCompleted: 0.6,
            color: .red,
        )
        .frame(width: 250, height: 20)

        HorizontalTimerProgressBarView(
            fractionCompleted: 0.75,
            color: .yellow,
            backgroundColor: .yellow,
        )
        .frame(width: 250, height: 20)

        HorizontalTimerProgressBarView(
            fractionCompleted: 1.0,
            color: .blue,
        )
        .frame(width: 250, height: 20)
    }
}
