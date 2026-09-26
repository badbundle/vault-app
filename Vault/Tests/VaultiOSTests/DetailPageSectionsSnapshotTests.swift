import Foundation
import SwiftUI
import TestHelpers
import Testing
import VaultFeed
@testable import VaultiOS

@MainActor
struct DetailPageSectionsSnapshotTests {
    /// Every card an item's page can end with, with its details open.
    @Test
    func allCards_detailsShowing() {
        let sut = Form {
            DetailItemBadgeSection(identity: .init(
                systemImage: "key.horizontal.fill",
                title: "GitHub",
                subtitle: "bradley@example.com",
                color: .init(red: 0.55, green: 0.36, blue: 0.96),
            ))
            DetailPageDescriptionSection(title: "Description", text: "Sign-in code for the badbundle org.")
            DetailPageInfoSections(
                tags: [
                    anyVaultItemTag(name: "Work", color: .tagDefault, iconName: "briefcase.fill"),
                    anyVaultItemTag(
                        name: "Personal",
                        color: .init(red: 0.2, green: 0.72, blue: 0.45),
                        iconName: "person.fill",
                    ),
                ],
                entries: [
                    DetailEntry(title: "Created", detail: "Jan 1, 1970 at 11:06 AM", systemIconName: "clock"),
                    DetailEntry(title: "Visibility", detail: "Always visible", systemIconName: "eye"),
                    DetailEntry(title: "Digits", detail: "6", systemIconName: "number"),
                ],
                isShowingDetails: true,
            )
        }

        for colorScheme in [ColorScheme.light, .dark] {
            for dynamicTypeSize in [DynamicTypeSize.medium, .xxLarge] {
                assertSnapshot(
                    of: sut.dynamicTypeSize(dynamicTypeSize).framedForTest(),
                    colorScheme: colorScheme,
                    named: "\(colorScheme)_\(dynamicTypeSize)",
                )
            }
        }
    }
}
