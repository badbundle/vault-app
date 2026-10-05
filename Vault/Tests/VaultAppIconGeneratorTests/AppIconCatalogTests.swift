import Foundation
import Testing
import VaultAppIcon
@testable import VaultAppIconGenerator

struct AppIconCatalogTests {
    @Test
    func entries_containEveryAppearanceOnceInOrder() {
        #expect(AppIconCatalog.entries.map(\.appearance) == VaultAppIconAppearance.allCases)
    }

    @Test
    func filename_matchesAppearance() {
        #expect(AppIconCatalog.filename(for: .light) == "AppIcon-Light.png")
        #expect(AppIconCatalog.filename(for: .dark) == "AppIcon-Dark.png")
        #expect(AppIconCatalog.filename(for: .tinted) == "AppIcon-Tinted.png")
    }

    @Test
    func imageURL_andContentsURL_liveInDirectory() {
        let directory = URL(filePath: "/tmp/AppIcon.appiconset", directoryHint: .isDirectory)
        let catalog = AppIconCatalog(directory: directory)
        let entry = AppIconCatalog.Entry(appearance: .dark, filename: "AppIcon-Dark.png")

        #expect(catalog.imageURL(for: entry).lastPathComponent == "AppIcon-Dark.png")
        #expect(catalog.imageURL(for: entry).path().hasPrefix(directory.path()))
        #expect(catalog.contentsURL.lastPathComponent == "Contents.json")
        #expect(catalog.contentsURL.path().hasPrefix(directory.path()))
    }

    @Test
    func contentsJSON_decodesToThreeAppearanceShape() throws {
        let contents = try JSONDecoder().decode(AssetCatalogContents.self, from: AppIconCatalog.contentsJSON())

        #expect(contents.info == AssetCatalogContents.Info(author: "xcode", version: 1))
        let filenames = ["AppIcon-Light.png", "AppIcon-Dark.png", "AppIcon-Tinted.png"]
        #expect(contents.images.map(\.filename) == filenames)
        #expect(contents.images.allSatisfy { $0.idiom == "universal" && $0.platform == "ios" })
        #expect(contents.images.allSatisfy { $0.size == "1024x1024" })
        #expect(contents.images[0].appearances == nil)
        #expect(contents.images[1].appearances == [.init(appearance: "luminosity", value: "dark")])
        #expect(contents.images[2].appearances == [.init(appearance: "luminosity", value: "tinted")])
    }

    @Test
    func contentsJSON_omitsAppearancesForTheDefaultSlot_andEndsWithNewline() throws {
        let json = try String(decoding: AppIconCatalog.contentsJSON(), as: UTF8.self)

        #expect(json.hasSuffix("\n"))
        // Two variants, so exactly two "appearances" keys: a null one on the
        // default slot would be a malformed catalog.
        #expect(json.components(separatedBy: "\"appearances\"").count == 3)
        #expect(!json.contains("null"))
    }

    @Test
    func defaultOutputPath_targetsTheAppIconSet() {
        #expect(AppIconCatalog.defaultOutputPath.hasSuffix("VaultApp/VaultApp/Assets.xcassets/AppIcon.appiconset"))
    }
}

struct MacAppIconCatalogTests {
    @Test
    func slots_areEveryMacSizeAtOneAndTwoTimes() {
        let slots = MacAppIconCatalog.slots.map { "\($0.points)@\($0.scale)x" }

        #expect(slots == [
            "16@1x",
            "16@2x",
            "32@1x",
            "32@2x",
            "128@1x",
            "128@2x",
            "256@1x",
            "256@2x",
            "512@1x",
            "512@2x",
        ])
    }

    @Test
    func pixelSizes_haveOneFileEachForEverySlot() {
        #expect(MacAppIconCatalog.pixelSizes == [16, 32, 64, 128, 256, 512, 1024])
        #expect(MacAppIconCatalog.slots.allSatisfy { MacAppIconCatalog.pixelSizes.contains($0.pixels) })
    }

    @Test
    func contentsJSON_listsEverySlotForTheMac() throws {
        let contents = try JSONDecoder().decode(
            MacAppIconCatalog.Contents.self,
            from: MacAppIconCatalog.contentsJSON(),
        )

        #expect(contents.images.count == 10)
        #expect(contents.images.allSatisfy { $0.idiom == "mac" })
        #expect(contents.images.first == .init(
            filename: "AppIcon-Mac-16.png",
            idiom: "mac",
            scale: "1x",
            size: "16x16",
        ))
        #expect(contents.images.last == .init(
            filename: "AppIcon-Mac-1024.png",
            idiom: "mac",
            scale: "2x",
            size: "512x512",
        ))
    }

    @Test
    func defaultOutputPath_targetsTheMacAppsIconSet() {
        #expect(MacAppIconCatalog.defaultOutputPath
            .hasSuffix("VaultApp/VaultMacApp/Assets.xcassets/AppIcon.appiconset"))
    }
}
