import Foundation
import SwiftUI

/// The icon at the leading edge of an option card: a white symbol on an accent square.
///
/// Shared by `OptionCardLabel` and `OptionCardToggle` so every card on a sheet has the same icon. It's decorative, so
/// VoiceOver skips it and reads the card's title instead.
struct OptionCardIcon: View {
    var systemImage: String

    @ScaledMetric(relativeTo: .title3) private var size: Double = 44

    var body: some View {
        Image(systemName: systemImage)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color.accentColor, in: .rect(cornerRadius: 12))
            .accessibilityHidden(true)
    }
}
