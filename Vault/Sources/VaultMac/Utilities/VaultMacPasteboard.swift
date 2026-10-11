import AppKit
import Foundation
import VaultCore
import VaultFeed
import VaultSettings

/// The Mac's clipboard, with the same rules as the iOS app's (G50): everything Vault copies is concealed from clipboard
/// managers, kept to this Mac unless Universal Clipboard is allowed for that kind of text, and cleared after the Clear
/// Clipboard time.
///
/// Every copy Vault makes on the Mac goes through here. A code a widget copies is put on the clipboard by the widget
/// extension, which the app then clears as it clears its own (`adoptWidgetCopy(_:now:)`).
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

    /// Takes over clearing a code a widget copied, as if Vault had copied it: once the Clear Clipboard time is up,
    /// counted from when the widget copied it, or when Vault locks or quits, unless something else has been copied
    /// since. Does nothing if something has already.
    func adoptWidgetCopy(_ copy: WidgetCopiedCode, now: Date = Date()) {
        let contents = VaultMacPasteboardContents(changeCount: copy.changeCount)
        guard system.adopt(contents) else { return }
        pendingClear?.cancel()
        guard let duration = localSettings.state.pasteTimeToLive.duration else {
            pendingClear = nil
            return
        }
        let timeToLive = max(0, copy.copiedAt.addingTimeInterval(duration).timeIntervalSince(now))
        pendingClear = Task { [system, sleep] in
            do {
                try await sleep(.seconds(timeToLive))
            } catch {
                return
            }
            system.clear(ifStill: contents)
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
    /// Takes `contents`, which a widget copied, as what Vault copied last, if nothing else has been copied since.
    /// Returns whether it did.
    func adopt(_ contents: VaultMacPasteboardContents) -> Bool
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

    func adopt(_ contents: VaultMacPasteboardContents) -> Bool {
        guard pasteboard.changeCount == contents.changeCount else { return false }
        lastCopied = contents
        return true
    }
}
