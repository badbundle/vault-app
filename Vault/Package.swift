// swift-tools-version: 6.0

import CompilerPluginSupport
import PackageDescription

let swiftLintVersion: Version = "0.65.1"
let swiftFormatVersion: Version = "0.63.0"
let swiftFormatChecksum: String = "d3c350a6655c0f687e2c23aac3e777b35345313a6428bb36b915fe7d9840ec78"

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableExperimentalFeature("AccessLevelOnImport"),
    .unsafeFlags(["-warnings-as-errors"]),
//    .unsafeFlags([
//        "-Xfrontend",
//        "-warn-long-function-bodies=100",
//        "-Xfrontend",
//        "-warn-long-expression-type-checking=100"
//    ]),
]

let targetPlugins: [Target.PluginUsage] = [
    .plugin(name: "RunMockolo"),
    .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins"),
]

let testTargetPlugins: [Target.PluginUsage] = [
    .plugin(name: "SwiftLintBuildToolPlugin", package: "SwiftLintPlugins"),
]

let package = Package(
    name: "Vault",
    defaultLocalization: "en",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(
            name: "VaultiOS",
            targets: ["VaultiOS"],
        ),
        .library(name: "VaultiOSAutofill", targets: ["VaultiOSAutofill"]),
        .library(name: "VaultiOSShared", targets: ["VaultiOSShared"]),
        .library(name: "VaultiOSWidgets", targets: ["VaultiOSWidgets"]),
        .executable(
            name: "vault-keygen-speedtest",
            targets: ["VaultKeygenSpeedtest"],
        ),
        .plugin(name: "FormatLint", targets: ["FormatLint"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", exact: "1.19.4"),
        .package(url: "https://github.com/attaswift/BigInt.git", exact: "6.0.1"),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift", exact: "1.10.0"),
        .package(url: "https://github.com/sunghyun-k/swiftui-toasts.git", exact: "1.1.1"),
        .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.8.2"),
        .package(url: "https://github.com/twostraws/CodeScanner", exact: "2.5.2"),
        .package(url: "https://github.com/dm-zharov/swift-security.git", exact: "2.5.1"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", exact: "2.4.1"),
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", exact: swiftLintVersion),
        .package(url: "https://github.com/swiftlang/swift-syntax", exact: "603.0.2"),
        // Tooling only: `make screenshots` runs its `framer` executable to put
        // marketing screenshots in device frames. Untagged upstream, so tracks
        // its main branch.
        .package(url: "https://github.com/badbundle/device-screenshot-framer", branch: "main"),
    ],
    targets: [
        .target(
            name: "VaultiOSShared",
            dependencies: [
                "VaultFeed",
            ],
            swiftSettings: swiftSettings,
            plugins: targetPlugins,
        ),
        .target(
            name: "VaultiOS",
            dependencies: [
                "VaultFeed",
                "VaultSettings",
                "VaultiOSShared",
                "CodeScanner",
                "FoundationExtensions",
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "Toasts", package: "swiftui-toasts"),
            ],
            resources: [
                .process("Resources/Feed.xcstrings"),
            ],
            swiftSettings: swiftSettings,
            plugins: targetPlugins,
        ),
        .testTarget(
            name: "VaultiOSTests",
            dependencies: [
                "VaultiOS",
                "VaultCore",
                "VaultFeed",
                "VaultSettings",
                "TestHelpers",
            ],
            exclude: ["__Snapshots__"],
            swiftSettings: swiftSettings,
            plugins: testTargetPlugins,
        ),
        .target(
            name: "VaultBackup",
            dependencies: ["VaultCore", "VaultKeygen", "VaultExport", "FoundationExtensions"],
            swiftSettings: swiftSettings,
            plugins: targetPlugins,
        ),
        .testTarget(
            name: "VaultBackupTests",
            dependencies: ["VaultBackup", "TestHelpers", "CryptoEngine"],
            exclude: ["__Snapshots__"],
            swiftSettings: swiftSettings,
            plugins: testTargetPlugins,
        ),
        .target(
            name: "TestHelpers",
            dependencies: [
                "FoundationExtensions",
                "TestHelpersMacros",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            swiftSettings: swiftSettings,
            plugins: targetPlugins,
        ),
        .macro(
            name: "TestHelpersMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ],
            swiftSettings: swiftSettings,
        ),
        .target(
            name: "VaultCore",
            dependencies: ["CryptoEngine", "FoundationExtensions"],
            swiftSettings: swiftSettings,
            plugins: targetPlugins,
        ),
        .testTarget(
            name: "VaultCoreTests",
            dependencies: ["VaultCore", "TestHelpers"],
            swiftSettings: swiftSettings,
            plugins: testTargetPlugins,
        ),
        .target(
            name: "VaultExport",
            dependencies: [
                "CryptoEngine",
                "FoundationExtensions",
                "ImageTools",
            ],
            swiftSettings: swiftSettings,
            plugins: targetPlugins,
        ),
        .testTarget(
            name: "VaultExportTests",
            dependencies: [
                "VaultExport",
                "ImageTools",
                "TestHelpers",
            ],
            exclude: ["__Snapshots__"],
            swiftSettings: swiftSettings,
            plugins: testTargetPlugins,
        ),
        .target(
            name: "ImageTools",
            dependencies: [
                "FoundationExtensions",
            ],
            swiftSettings: swiftSettings,
            plugins: targetPlugins,
        ),
        .testTarget(
            name: "ImageToolsTests",
            dependencies: [
                "ImageTools",
                "TestHelpers",
                .product(
                    name: "SnapshotTesting",
                    package: "swift-snapshot-testing",
                ),
            ],
            exclude: ["__Snapshots__"],
            swiftSettings: swiftSettings,
            plugins: testTargetPlugins,
        ),
        .target(
            name: "CryptoEngine",
            dependencies: ["FoundationExtensions", "CryptoSwift", "BigInt"],
            swiftSettings: swiftSettings,
            plugins: targetPlugins,
        ),
        .testTarget(
            name: "CryptoEngineTests",
            dependencies: ["CryptoEngine", "TestHelpers"],
            swiftSettings: swiftSettings,
            plugins: testTargetPlugins,
        ),
        .target(
            name: "VaultSettings",
            dependencies: [
                "FoundationExtensions",
                "VaultCore",
            ],
            resources: [
                .process("Resources/Settings.xcstrings"),
            ],
            swiftSettings: swiftSettings,
            plugins: targetPlugins,
        ),
        .testTarget(
            name: "VaultSettingsTests",
            dependencies: ["VaultSettings", "TestHelpers"],
            swiftSettings: swiftSettings,
            plugins: testTargetPlugins,
        ),
        .target(
            name: "VaultFeed",
            dependencies: [
                "VaultBackup",
                "VaultCore",
                "CryptoEngine",
                "FoundationExtensions",
                .product(name: "SwiftSecurity", package: "swift-security"),
            ],
            resources: [
                .process("Resources/VaultFeed.xcstrings"),
            ],
            swiftSettings: swiftSettings,
            plugins: targetPlugins,
        ),
        .testTarget(
            name: "VaultFeedTests",
            dependencies: ["VaultFeed", "VaultBackup", "VaultCore", "FoundationExtensions", "TestHelpers"],
            swiftSettings: swiftSettings,
            plugins: testTargetPlugins,
        ),
        .target(
            name: "FoundationExtensions",
            swiftSettings: swiftSettings,
            plugins: targetPlugins,
        ),
        .testTarget(
            name: "FoundationExtensionsTests",
            dependencies: ["FoundationExtensions", "TestHelpers"],
            swiftSettings: swiftSettings,
            plugins: testTargetPlugins,
        ),
        .target(
            name: "VaultKeygen",
            dependencies: ["CryptoEngine", "FoundationExtensions"],
            swiftSettings: swiftSettings,
            plugins: targetPlugins,
        ),
        .testTarget(
            name: "VaultKeygenTests",
            dependencies: ["VaultKeygen", "TestHelpers"],
            swiftSettings: swiftSettings,
            plugins: testTargetPlugins,
        ),
        .executableTarget(
            name: "VaultKeygenSpeedtest",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "CryptoEngine",
                "VaultKeygen",
            ],
            swiftSettings: swiftSettings,
        ),
        .testTarget(
            name: "VaultKeygenSpeedtestCompileTests",
            dependencies: ["VaultKeygenSpeedtest"],
            swiftSettings: swiftSettings,
        ),
        .target(
            name: "VaultiOSAutofill",
            dependencies: ["VaultCore", "VaultiOS"],
            swiftSettings: swiftSettings,
            plugins: targetPlugins,
        ),
        .testTarget(
            name: "VaultiOSAutofillTests",
            dependencies: ["VaultiOSAutofill", "TestHelpers"],
            swiftSettings: swiftSettings,
            plugins: testTargetPlugins,
        ),
        .target(
            name: "VaultiOSWidgets",
            dependencies: [
                "CryptoEngine",
                "FoundationExtensions",
                "VaultCore",
                "VaultFeed",
                "VaultiOSShared",
            ],
            swiftSettings: swiftSettings,
            plugins: targetPlugins,
        ),
        .testTarget(
            name: "VaultiOSWidgetsTests",
            dependencies: ["VaultiOSWidgets", "VaultiOSShared", "VaultCore", "VaultFeed", "TestHelpers"],
            swiftSettings: swiftSettings,
            plugins: testTargetPlugins,
        ),

        // MARK: - TOOLING

        .plugin(
            name: "RunMockolo",
            capability: .buildTool(),
            dependencies: [.target(name: "mockolo")],
        ),
        .binaryTarget(
            name: "mockolo",
            url: "https://github.com/uber/mockolo/releases/download/2.6.1/mockolo.artifactbundle.zip",
            checksum: "8ed3fd73a7b76b87b3d53cd702e5b977443d4ffd00d50161200e2526fc08e7bf",
        ),

        .plugin(
            name: "FormatLint",
            capability: .command(
                intent: .custom(
                    verb: "format",
                    description: "Formats Swift source files using swiftformat only",
                ),
                permissions: [.writeToPackageDirectory(reason: "Format source code")],
            ),
            dependencies: [
                "swiftformat",
            ],
        ),
        .binaryTarget(
            name: "swiftformat",
            url: "https://github.com/nicklockwood/SwiftFormat/releases/download/\(swiftFormatVersion)/swiftformat.artifactbundle.zip",
            checksum: swiftFormatChecksum,
        ),
    ],
)
