import Foundation
import SwiftUI
import TestHelpers
import Testing
import VaultFeed
@testable import VaultiOS

@MainActor
struct TagPillViewSnapshotTests {
    @Test
    func darkColored() {
        let tag = VaultItemTag(id: .new(), name: "Dark Color", color: .init(red: 0.05, green: 0.1, blue: 0.02))

        snapshotScenarios(tag: tag)
    }

    @Test
    func midColored() {
        let tag = VaultItemTag(id: .new(), name: "Mid Color", color: .init(red: 0.5, green: 0.5, blue: 0.5))

        snapshotScenarios(tag: tag)
    }

    @Test
    func lightColored() {
        let tag = VaultItemTag(id: .new(), name: "Light Color", color: .init(red: 1, green: 1, blue: 1))

        snapshotScenarios(tag: tag)
    }

    /// The size the feed's filters and an item's metadata use.
    @Test
    func compactSize() {
        let tag = VaultItemTag(
            id: .new(),
            name: "Work",
            color: .init(red: 0.2, green: 0.47, blue: 0.96),
            iconName: "briefcase.fill",
        )

        snapshotScenarios(tag: tag, controlSize: .small)
    }
}

extension TagPillViewSnapshotTests {
    func snapshotScenarios(tag: VaultItemTag, controlSize: ControlSize = .regular, testName: String = #function) {
        for isSelected in [true, false] {
            let tagView = TagPillView(tag: tag, isSelected: isSelected)
                .controlSize(controlSize)
            let isSelectedName = isSelected ? "selected" : "no-selected"
            for colorScheme in ColorScheme.allCases {
                let colorSchemeName = colorScheme.description
                let sut = tagView
                    .frame(width: 300, height: 200)
                    .background(Color(UIColor.systemBackground))
                    .environment(\.colorScheme, colorScheme)
                // The pill's glass resolves its content's colors from the
                // host's traits, which the environment alone doesn't set.
                let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)

                let config = [isSelectedName, colorSchemeName].joined(separator: ".")
                assertSnapshot(of: sut, as: .image(traits: traits), named: config, testName: testName)
            }
        }
    }
}

extension ColorScheme: @retroactive CustomStringConvertible {
    public var description: String {
        switch self {
        case .light: "light"
        case .dark: "dark"
        @unknown default: "unknown"
        }
    }
}
