import Foundation
import VaultAppIcon

/// Where the Mac's generated icon goes and what it's made of.
///
/// The Mac's icon is an Icon Composer document: a folder holding `icon.json` and the layer images it names. macOS 26
/// draws every app icon in its own rounded square, and an icon image that isn't that shape, such as one with its own
/// corners and shadow, is shrunk onto a grey tile. The document gives the system the artwork full bleed, as an iOS icon
/// does, so the system masks it. Xcode compiles it into every size the app and the App Store take, so the Mac app has
/// no `.appiconset`.
///
/// Pure bookkeeping, kept apart from rendering and file I/O so it can be tested without a graphics context or the disk.
struct MacIconComposerDocument: Sendable {
    /// `swift run` executes from `Vault/`, so this reaches the Mac app's folder, which Xcode includes wholesale.
    static let defaultOutputPath = "../VaultApp/VaultMacApp/AppIcon.icon"
    /// The side of Icon Composer's canvas, in points: a layer image this many pixels square covers it at 1x.
    static let pixelSize = 1024

    var directory: URL

    var assetsDirectory: URL {
        directory.appending(path: "Assets", directoryHint: .isDirectory)
    }

    var jsonURL: URL {
        directory.appending(path: "icon.json")
    }

    func imageURL(for appearance: VaultAppIconAppearance) -> URL {
        assetsDirectory.appending(path: Self.imageName(for: appearance))
    }

    /// The door and wheel in one appearance, on transparency.
    static func imageName(for appearance: VaultAppIconAppearance) -> String {
        switch appearance {
        case .light: "Glyph-Light.png"
        case .dark: "Glyph-Dark.png"
        case .tinted: "Glyph-Tinted.png"
        }
    }

    /// `icon.json`, laid out the way Icon Composer writes it itself so the diff stays quiet.
    static func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(IconDocument.vaultMac)
        data.append(contentsOf: [0x0A])
        return data
    }
}

/// The subset of Icon Composer's `icon.json` the Mac's icon uses.
struct IconDocument: Codable, Equatable, Sendable {
    /// A value for one appearance, or with no appearance, for the default one.
    struct Specialization<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
        /// `dark` or `tinted`, or `nil` for the default appearance.
        var appearance: String?
        var value: Value
    }

    struct Fill: Codable, Equatable, Sendable {
        var solid: String
    }

    struct Layer: Codable, Equatable, Sendable {
        var glass: Bool
        var imageNameSpecializations: [Specialization<String>]
        var name: String

        enum CodingKeys: String, CodingKey {
            case glass
            case imageNameSpecializations = "image-name-specializations"
            case name
        }
    }

    struct Shadow: Codable, Equatable, Sendable {
        /// `neutral`, `layer-color` or `none`.
        var kind: String
        var opacity: Double
    }

    struct Translucency: Codable, Equatable, Sendable {
        var enabled: Bool
        var value: Double
    }

    /// Layers the system lights, shadows and blurs as one piece.
    struct Group: Codable, Equatable, Sendable {
        var layers: [Layer]
        var shadow: Shadow
        var specular: Bool
        var translucency: Translucency
    }

    struct SupportedPlatforms: Codable, Equatable, Sendable {
        var squares: [String]
    }

    var fillSpecializations: [Specialization<Fill>]
    /// Front to back.
    var groups: [Group]
    var supportedPlatforms: SupportedPlatforms

    enum CodingKeys: String, CodingKey {
        case fillSpecializations = "fill-specializations"
        case groups
        case supportedPlatforms = "supported-platforms"
    }
}

extension IconDocument {
    /// The Mac's icon: the iOS icon's door and wheel on its white background, or silver on near black in the dark
    /// appearance, with the tinted glyph for the system to colour.
    ///
    /// It's flat, as the iOS icon is: no glass, lighting or shadow on the glyph, only the edges the system gives every
    /// icon.
    static let vaultMac = IconDocument(
        fillSpecializations: [
            Specialization(appearance: nil, value: Fill(solid: IconComposerColor.srgb(white: 1))),
            // Near black, as the backdrop iOS draws behind a dark icon is, rather than the dark icon's transparency.
            Specialization(
                appearance: "dark",
                value: Fill(solid: IconComposerColor.srgb(red: 0.10, green: 0.10, blue: 0.11)),
            ),
        ],
        groups: [
            Group(
                layers: [
                    Layer(
                        glass: false,
                        imageNameSpecializations: VaultAppIconAppearance.allCases.map { appearance in
                            Specialization(
                                appearance: appearance.iconComposerAppearance,
                                value: MacIconComposerDocument.imageName(for: appearance),
                            )
                        },
                        name: "Glyph",
                    ),
                ],
                shadow: Shadow(kind: "none", opacity: 0.5),
                specular: false,
                translucency: Translucency(enabled: false, value: 0.5),
            ),
        ],
        supportedPlatforms: SupportedPlatforms(squares: ["macOS"]),
    )
}

extension VaultAppIconAppearance {
    /// The appearance as Icon Composer names it, or `nil` for the default one.
    var iconComposerAppearance: String? {
        switch self {
        case .light: nil
        case .dark: "dark"
        case .tinted: "tinted"
        }
    }
}

/// A colour as Icon Composer writes one: `srgb:` then the four components to five places.
enum IconComposerColor {
    static func srgb(red: Double, green: Double, blue: Double, opacity: Double = 1) -> String {
        "srgb:" + [red, green, blue, opacity].map { String(format: "%.5f", $0) }.joined(separator: ",")
    }

    static func srgb(white: Double) -> String {
        srgb(red: white, green: white, blue: white)
    }
}
