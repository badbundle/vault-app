import Foundation

/// Where the Mac's generated icon files go, and the asset catalog that lists them.
///
/// A Mac app icon has five sizes in points, each at 1x and 2x. Several of those share a size in pixels, so each pixel
/// size is one file.
struct MacAppIconCatalog: Sendable {
    /// `swift run` executes from `Vault/`, so this reaches the Mac app's asset catalog.
    static let defaultOutputPath = "../VaultApp/VaultMacApp/Assets.xcassets/AppIcon.appiconset"

    struct Slot: Equatable, Sendable {
        /// The size in points.
        var points: Int
        var scale: Int

        var pixels: Int {
            points * scale
        }
    }

    /// Every slot of a Mac app icon, in the order Xcode lists them.
    static let slots: [Slot] = [16, 32, 128, 256, 512].flatMap { points in
        [Slot(points: points, scale: 1), Slot(points: points, scale: 2)]
    }

    /// Each size in pixels the slots need, smallest first.
    static let pixelSizes: [Int] = Array(Set(slots.map(\.pixels))).sorted()

    static func filename(pixels: Int) -> String {
        "AppIcon-Mac-\(pixels).png"
    }

    var directory: URL

    func imageURL(pixels: Int) -> URL {
        directory.appending(path: Self.filename(pixels: pixels))
    }

    var contentsURL: URL {
        directory.appending(path: "Contents.json")
    }

    /// The `Contents.json` for the Mac's icon, laid out the way Xcode writes it.
    static func contentsJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(Contents(
            images: slots.map { slot in
                .init(
                    filename: filename(pixels: slot.pixels),
                    idiom: "mac",
                    scale: "\(slot.scale)x",
                    size: "\(slot.points)x\(slot.points)",
                )
            },
            info: .init(author: "xcode", version: 1),
        ))
        data.append(contentsOf: [0x0A])
        return data
    }

    /// The subset of the asset catalog's `Contents.json` schema a Mac app icon uses.
    struct Contents: Codable, Equatable, Sendable {
        struct Image: Codable, Equatable, Sendable {
            var filename: String
            var idiom: String
            var scale: String
            var size: String
        }

        var images: [Image]
        var info: AssetCatalogContents.Info
    }
}
