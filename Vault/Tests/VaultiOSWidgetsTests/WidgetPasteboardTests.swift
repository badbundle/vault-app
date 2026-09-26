import Foundation
import FoundationExtensions
import TestHelpers
import Testing
import VaultCore
import VaultSettings
@testable import VaultiOSWidgets

@MainActor
struct WidgetPasteboardTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test
    func copyOTP_clearsAfterTheDefaultTimeIfNoneWasChosen() throws {
        let copy = try copyOTP(settings: .nonPersistent())

        #expect(copy.string == "123456")
        #expect(copy.expiresAt == now.addingTimeInterval(60))
    }

    @Test
    func copyOTP_clearsAfterTheChosenTime() throws {
        let settings = try Defaults.nonPersistent()
        try settings.set(PasteTTL(duration: 30), for: Key(VaultIdentifiers.Preferences.General.settingsPasteTTL))

        let copy = try copyOTP(settings: settings)

        #expect(copy.expiresAt == now.addingTimeInterval(30))
    }

    @Test
    func copyOTP_keepsTheCodeIfNeverWasChosen() throws {
        let settings = try Defaults.nonPersistent()
        try settings.set(PasteTTL(duration: nil), for: Key(VaultIdentifiers.Preferences.General.settingsPasteTTL))

        let copy = try copyOTP(settings: settings)

        #expect(copy.expiresAt == nil)
    }

    @Test
    func copyOTP_alwaysStaysOnThisDevice() throws {
        let copy = try copyOTP(settings: .nonPersistent())

        #expect(copy.localOnly)
    }
}

// MARK: - Helpers

extension WidgetPasteboardTests {
    private struct Copy {
        var string: String
        var expiresAt: Date?
        var localOnly: Bool
    }

    private func copyOTP(settings: Defaults) throws -> Copy {
        var copies = [Copy]()
        WidgetPasteboard.copyOTP("123456", settings: settings, now: now) { string, expiresAt, localOnly in
            copies.append(Copy(string: string, expiresAt: expiresAt, localOnly: localOnly))
        }
        return try #require(copies.first)
    }
}
