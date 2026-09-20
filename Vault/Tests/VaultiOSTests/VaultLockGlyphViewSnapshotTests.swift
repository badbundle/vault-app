import Foundation
import SwiftUI
import TestHelpers
import Testing
import UIKit
import VaultAppIcon
@testable import VaultiOS

@MainActor
struct VaultLockGlyphViewSnapshotTests {
    @Test
    func closed_light() throws {
        try assertSnapshot(of: render(makeSUT()), as: .image)
    }

    @Test
    func wheelRotated45_light() throws {
        try assertSnapshot(of: render(makeSUT(wheelRotation: .degrees(45))), as: .image)
    }

    @Test
    func doorOpen_light() throws {
        try assertSnapshot(of: render(makeSUT(doorOpening: VaultLockChoreography.openedDoor)), as: .image)
    }

    @Test
    func closed_dark() throws {
        try assertSnapshot(of: render(makeSUT(appearance: .dark, background: .black)), as: .image)
    }

    @Test
    func closed_compact_light() throws {
        try assertSnapshot(of: render(makeSUT(metrics: .compact)), as: .image)
    }
}

// MARK: - Helpers

extension VaultLockGlyphViewSnapshotTests {
    private func makeSUT(
        wheelRotation: Angle = .zero,
        doorOpening: Double = 0,
        appearance: VaultAppIconAppearance = .light,
        metrics: VaultIconMetrics = .standard,
        background: Color = .white,
    ) -> some View {
        VaultLockGlyphView(
            wheelRotation: wheelRotation,
            doorOpening: doorOpening,
            appearance: appearance,
            metrics: metrics,
        )
        .frame(width: 256, height: 256)
        .background(background)
    }

    /// Rendered with `ImageRenderer` rather than from the view's layer: the door
    /// swings on a `rotation3DEffect`, which `CALayer.render(in:)` flattens away.
    /// Same 3x scale as the device the other snapshots are recorded on.
    private func render(_ view: some View) throws -> UIImage {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        return try #require(renderer.uiImage)
    }
}
