import Foundation
import SwiftUI

/// A large, tappable choice: an icon on a colored square, a title with a subtitle beneath, and a chevron.
///
/// The new-item picker offers each kind of item this way, and an item's editor offers each of its parts the same way,
/// so choosing what to make and choosing what to change look alike. It draws no background: the container gives it
/// its card.
struct OptionCardLabel: View {
    var title: String
    var subtitle: String
    var systemImage: String
    var color: Color = .accentColor

    var body: some View {
        HStack(spacing: 14) {
            OptionCardIcon(systemImage: systemImage, color: color)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color(uiColor: .label))
                Text(subtitle)
                    .font(.subheadline)
                    // Explicit, so a button in a list doesn't tint it.
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            }
            .multilineTextAlignment(.leading)
            // A sheet that measures this to size itself would otherwise lay it out in a zero-height sheet first, and
            // truncate the text to one line. Sizing the text to its own height lets the subtitle wrap.
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The whole card is the target, not just the text.
        .contentShape(.rect)
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    OptionCardLabel(title: "Code", subtitle: "2FA timer or counter based codes", systemImage: "qrcode")
        .padding()
}
