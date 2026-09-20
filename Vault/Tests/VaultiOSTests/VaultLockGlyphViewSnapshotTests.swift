import Foundation
import SwiftUI
import TestHelpers
import Testing
import VaultAppIcon
@testable import VaultiOS

@MainActor
struct VaultLockGlyphViewSnapshotTests {
    @Test
    func closed_light() {
        assertSnapshot(of: makeSUT(), as: .image)
    }

    @Test
    func wheelRotated45_light() {
        assertSnapshot(of: makeSUT(wheelRotation: .degrees(45)), as: .image)
    }

    @Test
    func doorOpen_light() {
        assertSnapshot(of: makeSUT(doorOpening: VaultLockChoreography.openedDoor), as: .image)
    }

    @Test
    func closed_dark() {
        assertSnapshot(of: makeSUT(appearance: .dark, background: .black), as: .image)
    }
}

// MARK: - Helpers

extension VaultLockGlyphViewSnapshotTests {
    private func makeSUT(
        wheelRotation: Angle = .zero,
        doorOpening: Double = 0,
        appearance: VaultAppIconAppearance = .light,
        background: Color = .white,
    ) -> some View {
        VaultLockGlyphView(wheelRotation: wheelRotation, doorOpening: doorOpening, appearance: appearance)
            .frame(width: 256, height: 256)
            .background(background)
    }
}
