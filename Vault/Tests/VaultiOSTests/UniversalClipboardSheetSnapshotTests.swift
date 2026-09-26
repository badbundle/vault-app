import Foundation
import SwiftUI
import TestHelpers
import Testing
import VaultSettings
@testable import VaultiOS

@MainActor
struct UniversalClipboardSheetSnapshotTests {
    @Test
    func off() throws {
        for colorScheme in [ColorScheme.light, .dark] {
            for dynamicTypeSize in [DynamicTypeSize.xSmall, .medium, .xxLarge] {
                let sut = try makeSUT(dynamicTypeSize: dynamicTypeSize)

                assertSnapshot(of: sut, colorScheme: colorScheme, named: "\(colorScheme)_\(dynamicTypeSize)")
            }
        }
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func codesOn(colorScheme: ColorScheme) throws {
        let sut = try makeSUT { state in
            state.allowUniversalClipboardForOTPs = true
        }

        assertSnapshot(of: sut, colorScheme: colorScheme, named: "\(colorScheme)")
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func notesOn(colorScheme: ColorScheme) throws {
        let sut = try makeSUT { state in
            state.allowUniversalClipboardForNotes = true
        }

        assertSnapshot(of: sut, colorScheme: colorScheme, named: "\(colorScheme)")
    }
}

// MARK: - Helpers

extension UniversalClipboardSheetSnapshotTests {
    private func makeSUT(
        dynamicTypeSize: DynamicTypeSize = .medium,
        configure: (inout LocalSettingsState) -> Void = { _ in },
    ) throws -> some View {
        let localSettings = try LocalSettings(defaults: .nonPersistent())
        configure(&localSettings.state)
        // The sheet sizes itself to this content, so the frame is the phone width only and the height comes from
        // the view.
        return UniversalClipboardSheet(localSettings: localSettings)
            .dynamicTypeSize(dynamicTypeSize)
            .frame(width: 390)
            .background(Color(UIColor.systemBackground))
    }
}
