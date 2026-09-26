import Foundation
import SwiftUI
import TestHelpers
import Testing
@testable import VaultiOS

@MainActor
struct CreateItemPickerViewSnapshotTests {
    @Test
    func layout() {
        let colorSchemes: [ColorScheme] = [.light, .dark]
        let dynamicTypeSizes: [DynamicTypeSize] = [.xSmall, .medium, .xxLarge]
        for colorScheme in colorSchemes {
            for dynamicTypeSize in dynamicTypeSizes {
                // The sheet sizes itself to this content, so the frame is
                // the phone width only and the height comes from the view.
                let sut = CreateItemPickerView { _ in }
                    .dynamicTypeSize(dynamicTypeSize)
                    .frame(width: 390)
                    .background(Color(UIColor.systemBackground))

                assertSnapshot(of: sut, colorScheme: colorScheme, named: "\(colorScheme)_\(dynamicTypeSize)")
            }
        }
    }
}
