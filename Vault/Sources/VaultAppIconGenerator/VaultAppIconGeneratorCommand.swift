// A command-line tool: reporting what it wrote to standard out is the point.
// swiftlint:disable no_direct_standard_out_logs

import ArgumentParser
import Foundation
import VaultAppIcon

/// `make app-icon`: renders the SwiftUI app icon into the app's asset catalog, or with `--mac`, the Mac app's.
@main
struct VaultAppIconGeneratorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "vault-app-icon-generator",
        abstract: "Renders the SwiftUI app icon (light, dark and tinted) into an AppIcon.appiconset.",
    )

    @Option(name: .shortAndLong, help: "The AppIcon.appiconset directory to write into.")
    var output: String?

    @Option(name: .shortAndLong, help: "Side length of each PNG, in pixels. iOS only: the Mac's has every size.")
    var size: Int = AppIconCatalog.pixelSize

    @Flag(help: "Render the Mac app's icon, at every size its asset catalog takes.")
    var mac = false

    mutating func run() async throws {
        if mac {
            try await renderMacIcon()
        } else {
            try await renderIOSIcon()
        }
    }

    private func renderMacIcon() async throws {
        let catalog = MacAppIconCatalog(
            directory: URL(filePath: output ?? MacAppIconCatalog.defaultOutputPath, directoryHint: .isDirectory),
        )
        try FileManager.default.createDirectory(at: catalog.directory, withIntermediateDirectories: true)
        for pixels in MacAppIconCatalog.pixelSizes {
            let png = try await MainActor.run {
                try AppIconPNGRenderer.macPNGData(pixelSize: pixels)
            }
            let url = catalog.imageURL(pixels: pixels)
            try png.write(to: url)
            print("Wrote \(url.path())")
        }
        try MacAppIconCatalog.contentsJSON().write(to: catalog.contentsURL)
        print("Wrote \(catalog.contentsURL.path())")
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
