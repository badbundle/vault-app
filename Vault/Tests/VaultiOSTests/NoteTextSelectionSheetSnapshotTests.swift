import Foundation
import SwiftUI
import TestHelpers
import Testing
@testable import VaultiOS

@MainActor
struct NoteTextSelectionSheetSnapshotTests {
    @Test
    func layout() {
        for colorScheme in [ColorScheme.light, .dark] {
            for dynamicTypeSize in [DynamicTypeSize.medium, .xxLarge] {
                let sut = makeSUT(dynamicTypeSize: dynamicTypeSize)

                assertSnapshot(of: sut, colorScheme: colorScheme, named: "\(colorScheme)_\(dynamicTypeSize)")
            }
        }
    }
}

// MARK: - Helpers

extension NoteTextSelectionSheetSnapshotTests {
    private func makeSUT(dynamicTypeSize: DynamicTypeSize) -> some View {
        NoteTextSelectionSheet(
            text: "# Home Wi-Fi\n\nNetwork: **Mackey-5G**\nPassword: `correct-horse-battery-staple`",
        )
        .dynamicTypeSize(dynamicTypeSize)
        .frame(width: 390, height: 400)
    }
}
