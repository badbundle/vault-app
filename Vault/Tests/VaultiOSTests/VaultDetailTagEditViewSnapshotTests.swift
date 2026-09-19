import Foundation
import SwiftUI
import TestHelpers
import Testing
import VaultFeed
@testable import VaultiOS

@MainActor
struct VaultDetailTagEditViewSnapshotTests {
    @Test
    func layout_selectedAndRemainingTags() {
        let sut = makeSUT(
            tagsThatAreSelected: [
                anyVaultItemTag(name: "Work", color: .tagDefault, iconName: "briefcase.fill"),
                anyVaultItemTag(name: "Snow", color: .white, iconName: "snowflake"),
            ],
            remainingTags: [
                anyVaultItemTag(name: "Personal", color: .gray, iconName: "tag.fill"),
                anyVaultItemTag(name: "Night", color: .black, iconName: "moon.fill"),
            ],
        )
        .framedForTest()

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func layout_noTagsSelected() {
        let sut = makeSUT(
            tagsThatAreSelected: [],
            remainingTags: [
                anyVaultItemTag(name: "Personal", color: .gray, iconName: "tag.fill"),
            ],
        )
        .framedForTest()

        assertSnapshot(of: sut, as: .image)
    }
}

// MARK: - Helpers

extension VaultDetailTagEditViewSnapshotTests {
    private func makeSUT(
        tagsThatAreSelected: [VaultItemTag],
        remainingTags: [VaultItemTag],
    ) -> some View {
        VaultDetailTagEditView(
            tagsThatAreSelected: tagsThatAreSelected,
            remainingTags: remainingTags,
            didAdd: { _ in },
            didRemove: { _ in },
        )
    }
}
