// A command-line tool: reporting what it wrote to standard out is the point.
// swiftlint:disable no_direct_standard_out_logs

import ArgumentParser
import Foundation
import VaultAppIcon

/// `make app-icon`: renders the SwiftUI app icon into the app's asset catalog.
@main
struct VaultAppIconGeneratorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "vault-app-icon-generator",
        abstract: "Renders the SwiftUI app icon (light, dark and tinted) into an AppIcon.appiconset.",
    )

    @Option(name: .shortAndLong, help: "The AppIcon.appiconset directory to write into.")
    var output: String = AppIconCatalog.defaultOutputPath

    @Option(name: .shortAndLong, help: "Side length of each PNG, in pixels.")
    var size: Int = AppIconCatalog.pixelSize

    mutating func run() async throws {
        let catalog = AppIconCatalog(directory: URL(filePath: output, directoryHint: .isDirectory))
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
