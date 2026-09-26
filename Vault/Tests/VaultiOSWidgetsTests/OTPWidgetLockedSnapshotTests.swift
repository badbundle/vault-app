import Foundation
import SwiftUI
import TestHelpers
import Testing
import UIKit
@testable import VaultiOSWidgets

/// The widget's locked placeholder, which it shows while the app lock is on and while the vault is encrypted with the
/// App Lock Password: nothing of any code.
@MainActor
struct OTPWidgetLockedSnapshotTests {
    @Test(arguments: [ColorScheme.light, .dark])
    func small(colorScheme: ColorScheme) {
        let view = OTPWidgetSmallView(snapshot: .locked)
            .padding(16)
            .frame(width: 170, height: 170)
            .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 22))

        snapshot(view, colorScheme: colorScheme)
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func accessoryRectangular(colorScheme: ColorScheme) {
        let view = OTPWidgetAccessoryRectangularView(snapshot: .locked)
            .frame(width: 172, height: 76)

        snapshot(view, colorScheme: colorScheme)
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func accessoryCircular(colorScheme: ColorScheme) {
        let view = OTPWidgetAccessoryCircularView(snapshot: .locked)
            .frame(width: 76, height: 76)

        snapshot(view, colorScheme: colorScheme)
    }

    private func snapshot(_ view: some View, colorScheme: ColorScheme, testName: String = #function) {
        let framed = view
            .padding(12)
            .background(Color(uiColor: .systemBackground))
            .environment(\.colorScheme, colorScheme)
        let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)

        assertSnapshot(
            of: framed,
            as: .image(traits: traits),
            named: "\(colorScheme)",
            testName: testName,
        )
    }
}
