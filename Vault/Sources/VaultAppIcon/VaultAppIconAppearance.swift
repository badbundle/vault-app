import SwiftUI

/// The Home Screen appearance an icon rendering is for.
///
/// Apple's rules (Xcode, "Configuring your app icon"): the default icon is opaque,
/// the dark icon has a transparent background so the system's dark backdrop shows
/// through, and the tinted icon is a grayscale image the system colors itself.
///
/// The door's frame and its wheel are one flat tone: black on the default icon's
/// white, and silver in the dark icon, where black would vanish into the backdrop.
/// Only the tinted icon gives the wheel a second tone.
public enum VaultAppIconAppearance: String, CaseIterable, Sendable {
    case light
    case dark
    case tinted

    /// Whether the icon paints its own background. Only the default icon does; the
    /// dark and tinted variants are the glyph alone on transparency.
    public var hasOpaqueBackground: Bool {
        switch self {
        case .light: true
        case .dark, .tinted: false
        }
    }

    public var palette: VaultAppIconPalette {
        switch self {
        case .light:
            VaultAppIconPalette(background: .white, door: Color(white: 0.10), wheel: Color(white: 0.10))
        case .dark:
            VaultAppIconPalette(background: .clear, door: Color(white: 0.90), wheel: Color(white: 0.90))
        case .tinted:
            // The system tints by brightness, so the frame is brightest and the
            // wheel a step down from it: still two tones once tinted.
            VaultAppIconPalette(background: .clear, door: Color(white: 1.0), wheel: Color(white: 0.70))
        }
    }
}

/// The colors one appearance of the icon is drawn with: a solid color each for the
/// background, the door and the wheel, with no lighting.
///
/// Every value is an explicit color, never a semantic one: the icon has to render
/// identically whatever color scheme the surrounding environment has, on screen and
/// in `ImageRenderer`.
public struct VaultAppIconPalette: Sendable {
    /// The icon's background, only painted for opaque appearances.
    public var background: Color
    /// The door's frame.
    public var door: Color
    /// The wheel on the door.
    public var wheel: Color

    public init(background: Color, door: Color, wheel: Color) {
        self.background = background
        self.door = door
        self.wheel = wheel
    }

    /// The door and wheel in one `color`, with no background: the glyph as a
    /// symbol, for drawing on a colored background.
    public static func monochrome(_ color: Color) -> VaultAppIconPalette {
        VaultAppIconPalette(background: .clear, door: color, wheel: color)
    }
}
