import Foundation
import SwiftUI
import TestHelpers
import Testing
@testable import VaultiOS

@MainActor
struct CreateItemPickerViewSnapshotTests {
    /// The new-item sheet's first step: choosing the kind of item.
    @Test
    func layout() {
        for colorScheme in [ColorScheme.light, .dark] {
            for dynamicTypeSize in [DynamicTypeSize.xSmall, .medium, .xxLarge] {
                let sut = CreateItemPickerView { _ in }
                    .dynamicTypeSize(dynamicTypeSize)
                    .framedForTest(height: 700)
                    // The sheet the choice is shown in.
                    .background(Color(UIColor.systemBackground))

                assertSnapshot(of: sut, colorScheme: colorScheme, named: "\(colorScheme)_\(dynamicTypeSize)")
            }
        }
    }

    /// At the largest text size each kind's icon sits above its name, which then wraps across the card.
    @Test(arguments: [ColorScheme.light, .dark])
    func layoutAtLargestTextSize(colorScheme: ColorScheme) {
        let sut = CreateItemPickerView { _ in }
            .dynamicTypeSize(.accessibility5)
            .framedForTest(height: 1800)
            .background(Color(UIColor.systemBackground))

        assertSnapshot(of: sut, colorScheme: colorScheme, named: "\(colorScheme)")
    }
}
