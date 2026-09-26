import Foundation
import SwiftUI

/// The icon at the leading edge of an option card: a white symbol on a colored square, the accent color unless the
/// card says otherwise.
///
/// Shared by `OptionCardLabel` and `OptionCardToggle` so every card on a sheet has the same icon. It's decorative, so
/// VoiceOver skips it and reads the card's title instead.
struct OptionCardIcon: View {
    var systemImage: String
    var color: Color = .accentColor

    @ScaledMetric(relativeTo: .title3) private var size: Double = 44

    var body: some View {
        Image(systemName: systemImage)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: .rect(cornerRadius: 12))
            .accessibilityHidden(true)
    }
}

extension View {
    /// Sits an option card's content on the sheet's glass, like the New Item picker's cards, with the whole card as
    /// the target.
    func optionCardBackground() -> some View {
        padding(16)
            .background(.fill.quaternary, in: .rect(cornerRadius: 20))
            .contentShape(.rect(cornerRadius: 20))
    }
}
