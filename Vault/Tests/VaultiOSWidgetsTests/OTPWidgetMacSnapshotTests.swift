#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import TestHelpers
import Testing
@testable import VaultiOSWidgets

/// The Mac's widget, which comes in the small size only: Vault locked, which it shows whenever the app hands over no
/// codes, a code, and a code that isn't handed over.
@MainActor
struct OTPWidgetMacSnapshotTests {
    @Test(arguments: Appearance.allCases)
    func locked(appearance: Appearance) {
        snapshot(.locked, appearance: appearance)
    }

    @Test(arguments: Appearance.allCases)
    func code(appearance: Appearance) {
        snapshot(.totp(.init(
            itemID: UUID(),
            issuer: "Example",
            accountName: "someone@example.com",
            code: "123456",
            digits: 6,
            // Ended long ago, so its timer is empty whenever the test runs.
            periodStart: Date(timeIntervalSince1970: 0),
            periodEnd: Date(timeIntervalSince1970: 30),
        )), appearance: appearance)
    }

    @Test(arguments: Appearance.allCases)
    func unavailable(appearance: Appearance) {
        snapshot(.unavailable, appearance: appearance)
    }

    enum Appearance: String, CaseIterable, Sendable {
        case light
        case dark

        var name: NSAppearance.Name {
            switch self {
            case .light: .aqua
            case .dark: .darkAqua
            }
        }
    }

    private func snapshot(_ snapshot: OTPWidgetSnapshot, appearance: Appearance, testName: String = #function) {
        let widget = OTPWidgetSmallView(snapshot: snapshot)
            .padding(16)
            .frame(width: 170, height: 170)
            .background(.fill.tertiary, in: .rect(cornerRadius: 22))
            .padding(12)

        assertSnapshot(
            of: widget,
            as: .macWindow(width: 194, height: 194, appearance: appearance.name),
            named: appearance.rawValue,
            testName: testName,
        )
    }
}
#endif
