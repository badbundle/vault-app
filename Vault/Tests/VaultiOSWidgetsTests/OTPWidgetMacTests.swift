#if os(macOS)
import AppIntents
import AppKit
import Foundation
import FoundationExtensions
import SwiftUI
import TestHelpers
import Testing
import VaultFeed
import WidgetKit
@testable import VaultiOSShared
@testable import VaultiOSWidgets

/// What's the Mac's own about its widgets (docs/mac-app.md, "Widgets").
@MainActor
struct OTPWidgetMacTests {
    /// The Mac's widget shows only the codes the app hands it, and never opens the vault, nor reads the App Group,
    /// which
    /// its extension doesn't have (G98).
    @Test
    func source_isTheCodesTheAppHandsOver() {
        guard case .handoff = OTPWidgetSource.platform else {
            Issue.record("The Mac's widget reads \(OTPWidgetSource.platform)")
            return
        }
    }

    /// The Lock Screen's sizes aren't on the Mac.
    @Test
    func families_areOnlyTheSmallOne() {
        #expect(OTPWidget.families == [.systemSmall])
    }

    /// The Mac app has no URL scheme (docs/mac-app.md, decision 2), so its widgets have no links: clicking one opens
    /// Vault.
    @Test
    func links_areNone() {
        #expect(OTPWidgetLink.itemDetail(itemID: UUID()) == nil)
        #expect(OTPWidgetLink.hotpIncrement(itemID: UUID()) == nil)
    }

    /// Only the widget runs its actions: nothing is offered to Shortcuts or Spotlight (decision 2).
    @Test
    func actions_areNotOfferedToShortcutsOrSpotlight() {
        #expect(!CopyTOTPCodeIntent.isDiscoverable)
        #expect(!IncrementAndCopyHOTPCodeIntent.isDiscoverable)
    }

    /// Copying a code asks for the Mac to be unlocked first, as on iOS (G45).
    @Test
    func copy_asksForTheMacToBeUnlocked() {
        #expect(CopyTOTPCodeIntent.authenticationPolicy == .requiresAuthentication)
    }

    /// A widget's code goes on the clipboard as the app's do (G87): concealed and transient. `WidgetPasteboardTests`
    /// checks it stays on this Mac.
    @Test
    func copy_isConcealedAndTransient() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }

        let changeCount = ConcealedPasteboard.copy("123456", localOnly: true, to: pasteboard)

        let item = try #require(pasteboard.pasteboardItems?.first)
        #expect(item.string(forType: .string) == "123456")
        #expect(item.types.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")))
        #expect(item.types.contains(NSPasteboard.PasteboardType("org.nspasteboard.TransientType")))
        #expect(changeCount == pasteboard.changeCount)
    }

    /// A widget's copy always stays on this Mac, and the widget leaves the app a note of it to clear, as it has no
    /// App Group to read the Clear Clipboard time from (G87).
    @Test
    func copyOTP_staysOnThisMacAndLeavesTheAppANote() throws {
        let keychain = InMemoryKeychain()
        let notified = SharedMutex(0)
        let notes = WidgetCopiedCodeStore(keychain: keychain) { notified.modify { $0 += 1 } }
        let now = Date(timeIntervalSince1970: 1_000_000)
        var copies = [(string: String, localOnly: Bool)]()

        WidgetPasteboard.copyOTP("123456", now: now, notes: notes) { string, localOnly in
            copies.append((string, localOnly))
            return 42
        }

        #expect(copies.map(\.string) == ["123456"])
        #expect(copies.map(\.localOnly) == [true])
        #expect(notes.take() == WidgetCopiedCode(changeCount: 42, copiedAt: now))
        #expect(notified.value == 1)
    }
}
#endif
