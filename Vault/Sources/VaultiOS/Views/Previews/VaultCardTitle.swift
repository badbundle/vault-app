import SwiftUI

/// An item's title on its card in the feed: an OTP code's issuer, or a note's
/// or encrypted item's title.
///
/// Every kind of card draws its title at this one size, whatever else the
/// card shows, so a title never makes one item look like a different kind of
/// item from another.
struct VaultCardTitle: View {
    var text: String
    var isEditing: Bool
    /// The most lines the title wraps onto, or `nil` for as many as fit.
    var lineLimit: Int?

    var body: some View {
        Text(text)
            .font(.title3.bold())
            .minimumScaleFactor(0.7)
            .allowsTightening(true)
            .foregroundStyle(isEditing ? .white : .primary)
            .lineLimit(lineLimit)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
