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

struct MacIconComposerDocumentTests {
    @Test
    func imageNames_areOnePerAppearance() {
        let names = VaultAppIconAppearance.allCases.map(MacIconComposerDocument.imageName(for:))

        #expect(names == ["Glyph-Light.png", "Glyph-Dark.png", "Glyph-Tinted.png"])
    }

    @Test
    func imagesAndJSON_liveInTheDocument() {
        let document = MacIconComposerDocument(directory: URL(
            filePath: "/tmp/AppIcon.icon",
            directoryHint: .isDirectory,
        ))

        #expect(document.imageURL(for: .dark).path() == "/tmp/AppIcon.icon/Assets/Glyph-Dark.png")
        #expect(document.jsonURL.path() == "/tmp/AppIcon.icon/icon.json")
    }

    @Test
    func json_isAFlatGlyphOnWhiteOrNearBlackForTheMac() throws {
        let document = try JSONDecoder().decode(IconDocument.self, from: MacIconComposerDocument.json())

        #expect(document == .vaultMac)
        #expect(document.supportedPlatforms.squares == ["macOS"])
        #expect(document.fillSpecializations.map(\.appearance) == [nil, "dark"])
        #expect(document.fillSpecializations.first?.value.solid == "srgb:1.00000,1.00000,1.00000,1.00000")
        let layers = document.groups.flatMap(\.layers)
        #expect(layers.count == 1)
        #expect(layers.allSatisfy { !$0.glass })
        #expect(layers.first?.imageNameSpecializations == [
            .init(appearance: nil, value: "Glyph-Light.png"),
            .init(appearance: "dark", value: "Glyph-Dark.png"),
            .init(appearance: "tinted", value: "Glyph-Tinted.png"),
        ])
    }

    /// The default appearance is the specialization with no appearance at all, not one named "light".
    @Test
    func json_leavesOutTheDefaultAppearancesName() throws {
        let json = try #require(String(data: MacIconComposerDocument.json(), encoding: .utf8))

        #expect(!json.contains("\"light\""))
        #expect(!json.contains("null"))
    }

    @Test
    func defaultOutputPath_targetsTheMacAppsFolder() {
        #expect(MacIconComposerDocument.defaultOutputPath.hasSuffix("VaultApp/VaultMacApp/AppIcon.icon"))
    }
}
