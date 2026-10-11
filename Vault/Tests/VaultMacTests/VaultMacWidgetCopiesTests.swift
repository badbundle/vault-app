import AppKit
import Foundation
import FoundationExtensions
import notify
import TestHelpers
import Testing
import VaultFeed
import VaultSettings
@testable import VaultMac

/// A code a widget copies is cleared by Vault's clipboard, as its own copies are (G87, G98).
@MainActor
struct VaultMacWidgetCopiesTests {
    /// The widget leaves a note and posts a Darwin notification, which the app hears.
    @Test
    func aWidgetsCopy_isTakenOverByVaultsClipboardOnceItsHeardOf() async throws {
        let env = try Environment()
        defer { env.pasteboard.releaseGlobally() }
        env.copyOnTheClipboard()
        env.sut.start(notificationCenter: NotificationCenter())

        try env.widget.leave(WidgetCopiedCode(changeCount: env.pasteboard.changeCount, copiedAt: Date()))
        try await waitUntil { env.keychain.data.value == nil }
        env.clipboard.clearNow()

        #expect(env.pasteboard.string(forType: .string) == nil)
    }

    /// One the app didn't hear of is taken over when it next becomes active.
    @Test
    func becomingActive_takesOverACopyNotHeardOf() throws {
        let env = try Environment()
        defer { env.pasteboard.releaseGlobally() }
        let notificationCenter = NotificationCenter()
        env.sut.start(notificationCenter: notificationCenter)
        env.copyOnTheClipboard()
        try env.leaveNoteWithoutTelling()

        notificationCenter.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        env.clipboard.clearNow()

        #expect(env.pasteboard.string(forType: .string) == nil)
        #expect(env.keychain.data.value == nil)
    }

    /// Or as Vault locks or quits.
    @Test
    func takeOver_aCopyNotHeardOf_isClearedWhenVaultLocks() throws {
        let env = try Environment()
        defer { env.pasteboard.releaseGlobally() }
        env.copyOnTheClipboard()
        try env.leaveNoteWithoutTelling()

        env.sut.takeOver()
        env.clipboard.clearNow()

        #expect(env.pasteboard.string(forType: .string) == nil)
        #expect(env.keychain.data.value == nil)
    }

    @Test
    func takeOver_somethingCopiedSince_isLeftAlone() throws {
        let env = try Environment()
        defer { env.pasteboard.releaseGlobally() }
        env.copyOnTheClipboard()
        try env.leaveNoteWithoutTelling()
        env.pasteboard.clearContents()
        env.pasteboard.setString("someone else's", forType: .string)

        env.sut.takeOver()
        env.clipboard.clearNow()

        #expect(env.pasteboard.string(forType: .string) == "someone else's")
    }
}

// MARK: - Helpers

extension VaultMacWidgetCopiesTests {
    @MainActor
    private struct Environment {
        let pasteboard = NSPasteboard.withUniqueName()
        /// The note's keychain item, which the app and the widget share.
        let keychain = NoteKeychainSpy()
        /// The widget's side, which posts a Darwin notification of this test's own.
        let widget: WidgetCopiedCodeStore
        let clipboard: VaultMacPasteboard
        let sut: VaultMacWidgetCopies

        init() throws {
            let notificationName = "com.badbundle.vault.tests.copied-code.\(UUID().uuidString)"
            widget = WidgetCopiedCodeStore(keychain: keychain) {
                notify_post(notificationName)
            }
            clipboard = try VaultMacPasteboard(
                system: NSPasteboardSystemPasteboard(pasteboard: pasteboard),
                localSettings: LocalSettings(defaults: .nonPersistent()),
                sleep: { _ in try await suspendForever() },
            )
            sut = VaultMacWidgetCopies(
                notes: WidgetCopiedCodeStore(keychain: keychain, notify: {}),
                pasteboard: clipboard,
                notificationName: notificationName,
            )
        }

        func copyOnTheClipboard() {
            pasteboard.clearContents()
            pasteboard.setString("123456", forType: .string)
        }

        /// Leaves a note of what's on the clipboard, as the widget does, without telling the app.
        func leaveNoteWithoutTelling() throws {
            try WidgetCopiedCodeStore(keychain: keychain, notify: {})
                .leave(WidgetCopiedCode(changeCount: pasteboard.changeCount, copiedAt: Date()))
        }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition())
    }
}

/// The note's keychain item, in memory.
private final class NoteKeychainSpy: WidgetKeychainStoring {
    let data = SharedMutex<Data?>(nil)

    func read() throws -> Data? {
        data.value
    }

    func save(_ newData: Data) throws {
        data.modify { $0 = newData }
    }

    func remove() throws {
        data.modify { $0 = nil }
    }
}
