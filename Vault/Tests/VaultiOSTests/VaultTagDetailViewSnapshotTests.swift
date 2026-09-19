import Foundation
import SwiftUI
import TestHelpers
import Testing
import VaultFeed
@testable import VaultiOS

@MainActor
struct VaultTagDetailViewSnapshotTests {
    @Test
    func layout_newTag() {
        let sut = VaultTagDetailView(
            viewModel: .init(dataModel: anyVaultDataModel(), existingTag: nil),
        )
        .framedForTest()

        assertSnapshot(of: sut, as: .image)
    }

    @Test
    func layout_existingTag() {
        let sut = VaultTagDetailView(
            viewModel: .init(
                dataModel: anyVaultDataModel(),
                existingTag: anyVaultItemTag(name: "Work", color: .tagDefault, iconName: "briefcase.fill"),
            ),
        )
        .framedForTest()

        assertSnapshot(of: sut, as: .image)
    }
}
