import Foundation
import SwiftUI
import VaultFeed

extension VaultItemTag {
    /// Returns the fill/background color for displaying this tag in pill form
    /// - Parameter isSelected: Whether the tag is in a selected state
    func fillColor(isSelected: Bool) -> Color {
        if isSelected {
            let baseColor = color.color
            let brightness = baseColor.percievedBrightness

            // For very light colors (near white), use neutral light gray
            if brightness > 0.9 {
                return Color.primary.opacity(0.08)
            }
            // For very dark colors (near black), use very subtle tint
            else if brightness < 0.15 {
                return Color.primary.opacity(0.06)
            }
            // For normal colors, use standard opacity
            else {
                return baseColor.opacity(0.2)
            }
        } else {
            // Unselected pills are transparent
            return .clear
        }
    }

    /// Returns the stroke/foreground color for displaying this tag in pill form
    /// - Parameter isSelected: Whether the tag is in a selected state
    func strokeColor(isSelected _: Bool) -> Color {
        // Use the readable foreground color that has good contrast
        readableForegroundColor()
    }

    /// Returns the fill color for the prominent `FormRow` icon square, which
    /// draws a white glyph on top.
    func prominentIconColor() -> Color {
        let baseColor = color.color

        // Near-white fills would hide the white glyph, so fall back to a neutral gray
        if baseColor.percievedBrightness > 0.9 {
            return .gray
        }
        return baseColor
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
