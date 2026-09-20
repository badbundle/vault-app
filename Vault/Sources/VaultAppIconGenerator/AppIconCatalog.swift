import Foundation
import VaultAppIcon

/// Where the generated icon files go and what they are called.
///
/// Pure bookkeeping, kept apart from rendering and file I/O so it can be tested
/// without a graphics context or the disk.
struct AppIconCatalog: Sendable {
    /// `swift run` executes from `Vault/`, so this reaches the app's asset catalog.
    static let defaultOutputPath = "../VaultApp/VaultApp/Assets.xcassets/AppIcon.appiconset"
    /// The one size Xcode wants for an iOS app icon; it derives every other size.
    static let pixelSize = 1024

    struct Entry: Equatable, Sendable {
        var appearance: VaultAppIconAppearance
        var filename: String
    }

    /// One PNG per appearance, in catalog order.
    static let entries: [Entry] = VaultAppIconAppearance.allCases.map { appearance in
        Entry(appearance: appearance, filename: AppIconCatalog.filename(for: appearance))
    }

    static func filename(for appearance: VaultAppIconAppearance) -> String {
        switch appearance {
        case .light: "AppIcon-Light.png"
        case .dark: "AppIcon-Dark.png"
        case .tinted: "AppIcon-Tinted.png"
        }
    }

    var directory: URL

    func imageURL(for entry: Entry) -> URL {
        directory.appending(path: entry.filename)
    }

    var contentsURL: URL {
        directory.appending(path: "Contents.json")
    }

    /// The `Contents.json` for an icon with default, dark and tinted appearances,
    /// laid out the way Xcode writes it itself so the diff stays quiet.
    static func contentsJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(AssetCatalogContents.appIcon(entries: entries))
        data.append(contentsOf: [0x0A])
        return data
    }
}

/// The subset of the asset-catalog `Contents.json` schema an app icon uses.
struct AssetCatalogContents: Codable, Equatable, Sendable {
    struct Appearance: Codable, Equatable, Sendable {
        var appearance: String
        var value: String
    }

    struct ImageEntry: Codable, Equatable, Sendable {
        /// Absent for the default (light) slot.
        var appearances: [Appearance]?
        var filename: String
        var idiom: String
        var platform: String
        var size: String
    }

    struct Info: Codable, Equatable, Sendable {
        var author: String
        var version: Int
    }

    var images: [ImageEntry]
    var info: Info

    static func appIcon(entries: [AppIconCatalog.Entry]) -> AssetCatalogContents {
        let side = AppIconCatalog.pixelSize
        return AssetCatalogContents(
            images: entries.map { entry in
                ImageEntry(
                    appearances: luminosity(for: entry.appearance),
                    filename: entry.filename,
                    idiom: "universal",
                    platform: "ios",
                    size: "\(side)x\(side)",
                )
            },
            info: Info(author: "xcode", version: 1),
        )
    }

    private static func luminosity(for appearance: VaultAppIconAppearance) -> [Appearance]? {
        switch appearance {
        case .light: nil
        case .dark: [Appearance(appearance: "luminosity", value: "dark")]
        case .tinted: [Appearance(appearance: "luminosity", value: "tinted")]
        }
    }
}
