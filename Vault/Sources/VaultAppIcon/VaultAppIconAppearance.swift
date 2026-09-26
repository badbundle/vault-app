import SwiftUI

/// The Home Screen appearance an icon rendering is for.
///
/// Apple's rules (Xcode, "Configuring your app icon"): the default icon is opaque,
/// the dark icon has a transparent background so the system's dark backdrop shows
/// through, and the tinted icon is a grayscale image the system colors itself.
///
/// Every appearance has the same two tones: the door's frame, and a wheel of blue
/// turned metal on it. The frame is black on the default icon's white and silver in
/// the dark icon, where black would vanish into the backdrop; the blue wheel carries
/// the color in both, as Apple's own dark icons carry their color onto the glyph.
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
                // White, with just enough fall-off to keep some depth.
                backgroundTop: Color(white: 1.0),
                backgroundBottom: Color(white: 0.955),
                door: VaultAppIconPalette.Metal(
                    lit: Color(white: 0.30),
                    base: Color(white: 0.10),
                    shaded: Color(white: 0.03),
                    highlight: Color.white.opacity(0.35),
                    shadow: .clear,
                ),
                wheel: .blue,
            )
        case .dark:
            VaultAppIconPalette(
                backgroundTop: Color(white: 0.20),
                backgroundBottom: Color(white: 0.06),
                door: VaultAppIconPalette.Metal(
                    lit: Color(white: 1.0),
                    base: Color(white: 0.90),
                    shaded: Color(white: 0.76),
                    highlight: Color.white.opacity(0.80),
                    shadow: Color.black.opacity(0.15),
                ),
                wheel: .blue,
            )
        case .tinted:
            // The system tints by brightness, so the frame is brightest and the
            // wheel a step down from it: still two tones once tinted.
            VaultAppIconPalette(
                backgroundTop: Color(white: 0.12),
                backgroundBottom: Color(white: 0.02),
                door: VaultAppIconPalette.Metal(
                    lit: Color(white: 1.0),
                    base: Color(white: 0.93),
                    shaded: Color(white: 0.82),
                    highlight: Color.white.opacity(0.60),
                    shadow: .clear,
                ),
                wheel: VaultAppIconPalette.Metal(
                    lit: Color(white: 1.0),
                    base: Color(white: 0.78),
                    shaded: Color(white: 0.52),
                    highlight: Color.white.opacity(0.85),
                    shadow: Color.black.opacity(0.22),
                ),
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
    /// The door's frame: the first of the glyph's two tones.
    public var door: Metal
    /// The wheel on the door: the second tone.
    public var wheel: Metal

    public init(backgroundTop: Color, backgroundBottom: Color, door: Metal, wheel: Metal) {
        self.backgroundTop = backgroundTop
        self.backgroundBottom = backgroundBottom
        self.door = door
        self.wheel = wheel
    }

    /// The door and wheel in one flat `color`, with no background or lighting: the
    /// glyph as a symbol, for drawing on a colored background.
    public static func monochrome(_ color: Color) -> VaultAppIconPalette {
        VaultAppIconPalette(backgroundTop: .clear, backgroundBottom: .clear, door: .flat(color), wheel: .flat(color))
    }

    public var backgroundGradient: LinearGradient {
        LinearGradient(colors: [backgroundTop, backgroundBottom], startPoint: .top, endPoint: .bottom)
    }
}

extension VaultAppIconPalette {
    /// One finish of metal, lit from above.
    ///
    /// The gradients are in unit points of whatever they fill, so the same finish
    /// lights the whole door and each small part of the wheel.
    public struct Metal: Sendable {
        /// Facing the light…
        public var lit: Color
        public var base: Color
        /// …and facing away from it.
        public var shaded: Color
        /// The light caught by edges that face it, and the streaks on turned faces.
        public var highlight: Color
        /// The shade along edges that face away, and between the streaks.
        public var shadow: Color

        public init(lit: Color, base: Color, shaded: Color, highlight: Color, shadow: Color) {
            self.lit = lit
            self.base = base
            self.shaded = shaded
            self.highlight = highlight
            self.shadow = shadow
        }

        /// One `color` all over, with no lighting.
        public static func flat(_ color: Color) -> Metal {
            Metal(lit: color, base: color, shaded: color, highlight: .clear, shadow: .clear)
        }

        /// The wheel of the default and dark icons: blue, like the app's accent.
        static let blue = Metal(
            lit: Color(red: 140 / 255, green: 220 / 255, blue: 255 / 255),
            base: Color(red: 30 / 255, green: 140 / 255, blue: 255 / 255),
            shaded: Color(red: 12 / 255, green: 70 / 255, blue: 190 / 255),
            highlight: Color.white.opacity(0.85),
            shadow: Color.black.opacity(0.22),
        )

        /// Lit at the top, shaded at the bottom: a flat face under light from above.
        var faceGradient: LinearGradient {
            LinearGradient(
                stops: [
                    .init(color: lit, location: 0),
                    .init(color: base, location: 0.5),
                    .init(color: shaded, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom,
            )
        }

        /// Across a cylinder lying on its side: the light catches just above the
        /// middle and the underside falls into shade.
        var cylinderGradient: LinearGradient {
            LinearGradient(
                stops: [
                    .init(color: base, location: 0),
                    .init(color: lit, location: 0.3),
                    .init(color: base, location: 0.65),
                    .init(color: shaded, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom,
            )
        }

        /// A dome `radius` across, lit from the top left.
        func domeGradient(radius: CGFloat) -> RadialGradient {
            RadialGradient(
                stops: [
                    .init(color: lit, location: 0),
                    .init(color: base, location: 0.55),
                    .init(color: shaded, location: 1),
                ],
                center: UnitPoint(x: 0.325, y: 0.275),
                startRadius: 0,
                endRadius: radius * 1.5,
            )
        }

        /// The streaks a lathe leaves on a turned face: bright towards the light
        /// and opposite it, dark across. Laid over a dome.
        var turnedStreaks: AngularGradient {
            let bright = highlight.opacity(0.5)
            let dark = shadow.opacity(0.8)
            let none = highlight.opacity(0)
            // Clockwise from pointing right: bottom right, bottom left, top left, top right.
            return AngularGradient(
                stops: [
                    .init(color: none, location: 0),
                    .init(color: bright.opacity(0.7), location: 0.125),
                    .init(color: none, location: 0.25),
                    .init(color: dark, location: 0.375),
                    .init(color: none, location: 0.5),
                    .init(color: bright, location: 0.625),
                    .init(color: none, location: 0.75),
                    .init(color: dark, location: 0.875),
                    .init(color: none, location: 1),
                ],
                center: .center,
            )
        }

        /// The rim: catching the light along the top, in shade along the bottom.
        var rimGradient: LinearGradient {
            LinearGradient(
                stops: [
                    .init(color: highlight, location: 0),
                    .init(color: highlight.opacity(0), location: 0.45),
                    .init(color: shadow.opacity(0), location: 0.55),
                    .init(color: shadow, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom,
            )
        }

        /// The inside of a hole, the rim reversed: the top edge faces down into the
        /// hole, away from the light, and the bottom edge faces up into it.
        var boreGradient: LinearGradient {
            LinearGradient(colors: [shadow, highlight.opacity(0.6)], startPoint: .top, endPoint: .bottom)
        }
    }
}
