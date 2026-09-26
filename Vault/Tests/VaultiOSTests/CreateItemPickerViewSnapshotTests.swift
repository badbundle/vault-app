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
}
