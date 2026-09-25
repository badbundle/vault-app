import Foundation
import SwiftUI
import VaultFeed

extension VaultItemTag {
    /// The name to show for this tag, with a placeholder while it is blank.
    var displayName: String {
        name.isBlank ? "Tag" : name
    }

    /// The fill of the tag's pill: clear, or while selected, a tint of its
    /// outline, so every tag shows its selection equally clearly.
    /// - Parameter isSelected: Whether the tag is in a selected state
    func fillColor(isSelected: Bool) -> Color {
        isSelected ? strokeColor.opacity(0.2) : .clear
    }

    /// The outline of the tag's pill: its color, adjusted where needed so it
    /// stands out on light and dark backgrounds alike.
    var strokeColor: Color {
        readableForegroundColor()
    }

    /// Returns a foreground color that's guaranteed to be readable
    private func readableForegroundColor() -> Color {
        let baseColor = color.color
        let brightness = baseColor.percievedBrightness

        // For very light/near-white colors, use semantic color with opacity
        if brightness > 0.9 {
            return Color.primary.opacity(0.7)
        }
        // For light colors (but not white), darken moderately
        else if brightness > 0.7 {
            return color.brighten(amount: -0.4).color
        }
        // For very dark colors, use semantic color with medium opacity
        else if brightness < 0.15 {
            return Color.primary.opacity(0.8)
        }
        // For dark colors, lighten significantly
        else if brightness < 0.3 {
            return color.brighten(amount: 0.6).color
        }
        // For medium colors, use as-is
        else {
            return baseColor
        }
    }
}

extension VaultItemColor {
    /// Fill color for a tag's badge, the circle that draws its white glyph on
    /// top.
    var badgeColor: Color {
        let baseColor = color

        // Near-white fills would hide the white glyph, so fall back to a
        // neutral gray. A plain RGB gray rather than a system one, which
        // glass renders as a vibrant fill that shifts with the backdrop, so
        // the badge matches inside and outside a glass pill.
        if baseColor.percievedBrightness > 0.9 {
            return VaultItemColor.gray.color
        }
        return baseColor
    }
}
