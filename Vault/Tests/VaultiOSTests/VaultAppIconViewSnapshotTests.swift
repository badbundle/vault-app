import Foundation
import SwiftUI
import TestHelpers
import Testing
import VaultAppIcon
@testable import VaultiOS

@MainActor
struct VaultAppIconViewSnapshotTests {
    @Test
    func appearance_light() {
        assertSnapshot(of: makeSUT(.light), as: .image)
    }

    @Test
    func appearance_dark() {
        assertSnapshot(of: makeSUT(.dark), as: .image)
    }

    @Test
    func appearance_tinted() {
        assertSnapshot(of: makeSUT(.tinted), as: .image)
    }
}

// MARK: - Helpers

extension VaultAppIconViewSnapshotTests {
    /// Dark and tinted are transparent (the system supplies their backgrounds),
    /// so every variant is laid over black to stand in for the Home Screen.
    private func makeSUT(_ appearance: VaultAppIconAppearance) -> some View {
        VaultAppIconView(appearance: appearance)
            .frame(width: 256, height: 256)
            .background(Color.black)
    }
}
