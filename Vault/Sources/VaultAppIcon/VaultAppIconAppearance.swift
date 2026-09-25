import SwiftUI

/// The Home Screen appearance an icon rendering is for.
///
/// Apple's rules (Xcode, "Configuring your app icon"): the default icon is opaque,
/// the dark icon has a transparent background so the system's dark backdrop shows
/// through, and the tinted icon is a grayscale image the system colors itself.
///
/// The default icon's aqua-to-blue background becomes the color of the door in the
/// dark icon, as Apple's own dark icons carry their color onto the glyph.
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
            VaultAppIconPalette(
                backgroundTop: .iconAqua,
                backgroundBottom: .iconBlue,
                metalTop: Color(white: 0.30),
                metalMiddle: Color(white: 0.10),
                metalBottom: Color(white: 0.03),
                highlight: Color.white.opacity(0.35),
            )
        case .dark:
            VaultAppIconPalette(
                backgroundTop: Color(white: 0.20),
                backgroundBottom: Color(white: 0.06),
                metalTop: .iconAqua,
                metalMiddle: .iconAqua.mix(with: .iconBlue, by: 0.5),
                metalBottom: .iconBlue,
                highlight: Color.white.opacity(0.65),
            )
        case .tinted:
            VaultAppIconPalette(
                backgroundTop: Color(white: 0.12),
                backgroundBottom: Color(white: 0.02),
                metalTop: Color(white: 0.98),
                metalMiddle: Color(white: 0.85),
                metalBottom: Color(white: 0.70),
                highlight: Color.white.opacity(0.50),
            )
        }
    }
}

/// The colors one appearance of the icon is drawn with.
///
/// Every value is an explicit color, never a semantic one: the icon has to render
/// identically whatever color scheme the surrounding environment has, on screen and
/// in `ImageRenderer`.
public struct VaultAppIconPalette: Sendable {
    /// Top of the icon background (only painted for opaque appearances).
    public var backgroundTop: Color
    public var backgroundBottom: Color
    /// The "brushed metal" of the door and wheel, top to bottom. In the dark icon
    /// the metal takes on the default icon's background colors.
    public var metalTop: Color
    public var metalMiddle: Color
    public var metalBottom: Color
    /// The thin rim light along the top edges.
    public var highlight: Color

    public init(
        backgroundTop: Color,
        backgroundBottom: Color,
        metalTop: Color,
        metalMiddle: Color,
        metalBottom: Color,
        highlight: Color,
    ) {
        self.backgroundTop = backgroundTop
        self.backgroundBottom = backgroundBottom
        self.metalTop = metalTop
        self.metalMiddle = metalMiddle
        self.metalBottom = metalBottom
        self.highlight = highlight
    }

    public var backgroundGradient: LinearGradient {
        LinearGradient(colors: [backgroundTop, backgroundBottom], startPoint: .top, endPoint: .bottom)
    }

    public var metalGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: metalTop, location: 0),
                .init(color: metalMiddle, location: 0.5),
                .init(color: metalBottom, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom,
        )
    }

    /// Bright at the top, gone by the middle: a rim light from above.
    public var highlightGradient: LinearGradient {
        LinearGradient(colors: [highlight, highlight.opacity(0)], startPoint: .top, endPoint: .center)
    }
}

extension Color {
    /// The top of the icon's gradient: a bright aqua…
    fileprivate static let iconAqua = Color(red: 134 / 255, green: 240 / 255, blue: 255 / 255)
    /// …deepening to a vivid blue at the bottom.
    fileprivate static let iconBlue = Color(red: 58 / 255, green: 140 / 255, blue: 255 / 255)
}
