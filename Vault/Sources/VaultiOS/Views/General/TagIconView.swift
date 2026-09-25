import Foundation
import SwiftUI
import VaultFeed

/// A tag's icon: its glyph in white on a circle of the tag's color.
///
/// Tags carry this one badge everywhere they appear, from the pills in the
/// feed to the rows of the tag list, so a tag is recognizable at a glance.
/// It is decorative: the tag's name always sits beside it.
struct TagIconView: View {
    var iconName: String
    var color: VaultItemColor
    /// The circle's diameter. Callers scale it with Dynamic Type.
    var size: Double

    var body: some View {
        Image(systemName: iconName)
            .font(.system(size: size * 0.5, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.badgeColor, in: .circle)
            .accessibilityHidden(true)
    }
}
