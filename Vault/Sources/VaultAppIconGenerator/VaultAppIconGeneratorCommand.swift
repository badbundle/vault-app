// A command-line tool: reporting what it wrote to standard out is the point.
// swiftlint:disable no_direct_standard_out_logs

import ArgumentParser
import Foundation
import VaultAppIcon

/// `make app-icon`: renders the SwiftUI app icon into the app's asset catalog, or with `--mac`, into the Mac app's Icon
/// Composer document.
@main
struct VaultAppIconGeneratorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "vault-app-icon-generator",
        abstract: "Renders the SwiftUI app icon (light, dark and tinted) into an AppIcon.appiconset, or the Mac's AppIcon.icon.",
    )

    @Option(
        name: .shortAndLong,
        help: "The AppIcon.appiconset directory to write into, or with --mac, the AppIcon.icon document.",
    )
    var output: String?

    @Option(name: .shortAndLong, help: "Side length of each PNG, in pixels. iOS only: the Mac's are always 1024.")
    var size: Int = AppIconCatalog.pixelSize

    @Flag(help: "Render the Mac app's icon, as an Icon Composer document.")
    var mac = false

    mutating func run() async throws {
        if mac {
            try await renderMacIcon()
        } else {
            try await renderIOSIcon()
        }
    }

    private func renderMacIcon() async throws {
        let document = MacIconComposerDocument(
            directory: URL(filePath: output ?? MacIconComposerDocument.defaultOutputPath, directoryHint: .isDirectory),
        )
        try FileManager.default.createDirectory(at: document.assetsDirectory, withIntermediateDirectories: true)
        for appearance in VaultAppIconAppearance.allCases {
            let png = try await MainActor.run {
                try AppIconPNGRenderer.glyphPNGData(
                    appearance: appearance,
                    pixelSize: MacIconComposerDocument.pixelSize,
                )
            }
            let url = document.imageURL(for: appearance)
            try png.write(to: url)
            print("Wrote \(url.path())")
        }
        try MacIconComposerDocument.json().write(to: document.jsonURL)
        print("Wrote \(document.jsonURL.path())")
    }

    private func renderIOSIcon() async throws {
        let catalog = AppIconCatalog(
            directory: URL(filePath: output ?? AppIconCatalog.defaultOutputPath, directoryHint: .isDirectory),
        )
        let pixelSize = size
        try FileManager.default.createDirectory(at: catalog.directory, withIntermediateDirectories: true)

        for entry in AppIconCatalog.entries {
            let png = try await MainActor.run {
                try AppIconPNGRenderer.pngData(appearance: entry.appearance, pixelSize: pixelSize)
            }
            let url = catalog.imageURL(for: entry)
            try png.write(to: url)
            print("Wrote \(url.path())")
        }

        try AppIconCatalog.contentsJSON().write(to: catalog.contentsURL)
        print("Wrote \(catalog.contentsURL.path())")
    }
}
