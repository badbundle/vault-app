import AppKit
import Foundation
import VaultCore
import VaultFeed
import VaultSettings

/// The Mac's clipboard, with the same rules as the iOS app's (G50): everything Vault copies is concealed from clipboard
/// managers, kept to this Mac unless Universal Clipboard is allowed for that kind of text, and cleared after the Clear
/// Clipboard time.
///
/// Every copy Vault makes on the Mac goes through here.
@MainActor
@Observable
final class VaultMacPasteboard {
    private let system: any VaultMacSystemPasteboard
    private let localSettings: LocalSettings
    private let sleep: @Sendable (Duration) async throws -> Void
    /// Clears what was copied last, once its time is up.
    @ObservationIgnored private(set) var pendingClear: Task<Void, Never>?

    init(
        system: any VaultMacSystemPasteboard,
        localSettings: LocalSettings,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
    ) {
        self.system = system
        self.localSettings = localSettings
        self.sleep = sleep
    }

    func copy(_ action: VaultTextCopyAction) {
        copy(action.text, as: action.contentType)
    }

    /// Copies `text`, following the clipboard settings.
    func copy(_ text: String, as contentType: PasteboardContentType) {
        let isCurrentHostOnly = !localSettings.state.isUniversalClipboardAllowed(for: contentType)
        let copied = system.copy(string: text, currentHostOnly: isCurrentHostOnly)
        pendingClear?.cancel()
        guard let timeToLive = localSettings.state.pasteTimeToLive.duration else {
            pendingClear = nil
            return
        }
        pendingClear = Task { [system, sleep] in
            do {
                try await sleep(.seconds(timeToLive))
            } catch {
                return
            }
            system.clear(ifStill: copied)
        }
    }

    /// Clears the clipboard now, if it still holds what Vault copied last: when Vault quits, which ends the timer that
    /// would have cleared it.
    func clearNow() {
        pendingClear?.cancel()
        pendingClear = nil
        system.clearIfStillCopiedByVault()
    }
}

/// What's on the clipboard once Vault has copied something: its change count, which changes when anything else is
/// copied.
struct VaultMacPasteboardContents: Equatable, Sendable {
    var changeCount: Int
}

/// The system clipboard, which tests stand in for.
@MainActor
protocol VaultMacSystemPasteboard: Sendable {
    /// Replaces the clipboard's contents with `string`, marked concealed and transient. Returns what's there now.
    func copy(string: String, currentHostOnly: Bool) -> VaultMacPasteboardContents
    /// Clears the clipboard, unless something else has been copied since `contents`.
    func clear(ifStill contents: VaultMacPasteboardContents)
    /// Clears the clipboard, if what Vault copied last is still on it.
    func clearIfStillCopiedByVault()
}

/// The Mac's general pasteboard.
@MainActor
final class NSPasteboardSystemPasteboard: VaultMacSystemPasteboard {
    /// Clipboard managers don't show a value marked with this (nspasteboard.org), as the iOS app marks its copies.
    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    /// Clipboard managers don't keep a value marked with this at all (nspasteboard.org).
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    private let pasteboard: NSPasteboard
    private var lastCopied: VaultMacPasteboardContents?

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func copy(string: String, currentHostOnly: Bool) -> VaultMacPasteboardContents {
        pasteboard.prepareForNewContents(with: currentHostOnly ? .currentHostOnly : [])
        let item = NSPasteboardItem()
        item.setString(string, forType: .string)
        item.setString(string, forType: Self.concealedType)
        item.setString("", forType: Self.transientType)
        pasteboard.writeObjects([item])
        let contents = VaultMacPasteboardContents(changeCount: pasteboard.changeCount)
        lastCopied = contents
        return contents
    }

    func clear(ifStill contents: VaultMacPasteboardContents) {
        guard pasteboard.changeCount == contents.changeCount else { return }
        pasteboard.clearContents()
        lastCopied = nil
    }

    func clearIfStillCopiedByVault() {
        guard let lastCopied else { return }
        clear(ifStill: lastCopied)
    }
}
