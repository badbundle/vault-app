import AppIntents
import Foundation
import SwiftUI
import TestHelpers
import Testing
import UIKit
@testable import VaultiOSWidgets

/// On the Lock Screen and in StandBy, the system redacts a widget's privacy-sensitive views until the iPhone is
/// unlocked (`.redacted(reason: .privacy)`), and runs its actions only once it's unlocked.
@MainActor
struct OTPWidgetLockScreenPrivacyTests {
    @Test
    func copyTOTPCode_asksForTheIPhoneToBeUnlocked() {
        #expect(CopyTOTPCodeIntent.authenticationPolicy == .requiresAuthentication)
    }

    @Test
    func incrementAndCopyHOTPCode_asksForTheIPhoneToBeUnlocked() {
        #expect(IncrementAndCopyHOTPCodeIntent.authenticationPolicy == .requiresAuthentication)
    }

    /// Redacted, a widget looks the same whatever its code is, so it shows none of the code's digits.
    @Test(arguments: WidgetFamilyView.allCases)
    func redacted_showsNoDigits(family: WidgetFamilyView) throws {
        let first = try render(family.view(snapshot: totp(code: "123456")).redacted(reason: .privacy))
        let second = try render(family.view(snapshot: totp(code: "987654")).redacted(reason: .privacy))

        #expect(first == second)
    }

    /// Unredacted, the digits show, so the redacted comparison means something.
    @Test(arguments: WidgetFamilyView.allCases)
    func unredacted_showsTheDigits(family: WidgetFamilyView) throws {
        let first = try render(family.view(snapshot: totp(code: "123456")))
        let second = try render(family.view(snapshot: totp(code: "987654")))

        #expect(first != second)
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func small_redacted(colorScheme: ColorScheme) {
        let view = WidgetFamilyView.small.view(snapshot: totp(code: "123456"))
            .redacted(reason: .privacy)

        snapshot(view, colorScheme: colorScheme)
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func accessoryRectangular_redacted(colorScheme: ColorScheme) {
        let view = WidgetFamilyView.accessoryRectangular.view(snapshot: totp(code: "123456"))
            .redacted(reason: .privacy)

        snapshot(view, colorScheme: colorScheme)
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func accessoryCircular_redacted(colorScheme: ColorScheme) {
        let view = WidgetFamilyView.accessoryCircular.view(snapshot: totp(code: "123456"))
            .redacted(reason: .privacy)

        snapshot(view, colorScheme: colorScheme)
    }

    /// The locked placeholder shows nothing of a code, so it stays readable while redacted.
    @Test
    func locked_redacted_isUnchanged() throws {
        for family in WidgetFamilyView.allCases {
            let redacted = try render(family.view(snapshot: .locked).redacted(reason: .privacy))
            let plain = try render(family.view(snapshot: .locked))

            #expect(redacted == plain, "\(family)")
        }
    }

    // MARK: - Helpers

    enum WidgetFamilyView: CaseIterable, CustomStringConvertible {
        case small
        case accessoryRectangular
        case accessoryCircular

        var description: String {
            switch self {
            case .small: "small"
            case .accessoryRectangular: "accessoryRectangular"
            case .accessoryCircular: "accessoryCircular"
            }
        }

        @MainActor
        @ViewBuilder
        func view(snapshot: OTPWidgetSnapshot) -> some View {
            switch self {
            case .small:
                OTPWidgetSmallView(snapshot: snapshot)
                    .padding(16)
                    .frame(width: 170, height: 170)
                    .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 22))
            case .accessoryRectangular:
                OTPWidgetAccessoryRectangularView(snapshot: snapshot)
                    .frame(width: 172, height: 76)
            case .accessoryCircular:
                OTPWidgetAccessoryCircularView(snapshot: snapshot)
                    .frame(width: 76, height: 76)
            }
        }
    }

    /// A code whose period ended long ago, so its timer is empty whenever the test runs.
    private func totp(code: String) -> OTPWidgetSnapshot {
        .totp(.init(
            itemID: UUID(),
            issuer: "Example",
            accountName: "someone@example.com",
            code: code,
            digits: code.count,
            periodStart: Date(timeIntervalSince1970: 0),
            periodEnd: Date(timeIntervalSince1970: 30),
        ))
    }

    private func render(_ view: some View) throws -> Data {
        let renderer = ImageRenderer(content: view.background(Color.white))
        renderer.scale = 2
        return try #require(renderer.uiImage?.pngData())
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
