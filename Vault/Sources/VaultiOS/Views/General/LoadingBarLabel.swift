import Foundation
import SwiftUI

/// The short message inside a code card's timer bar, such as "Code expired".
///
/// It's small enough to sit inside the bar with room to spare, and grows with Dynamic Type only as far as the
/// bar does (see ``CodeStateTimerBarMetrics``), so it never clips. It has no color of its own: the bar colors it
/// to contrast with whatever is behind it.
struct LoadingBarLabel: View {
    var text: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Text(text)
            .font(.system(size: CodeStateTimerBarMetrics.labelFontSize(for: dynamicTypeSize), weight: .bold))
            .tracking(0.3)
            .textCase(.uppercase)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 6)
    }
}
