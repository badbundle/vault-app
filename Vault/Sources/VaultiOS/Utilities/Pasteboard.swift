import Combine
import Foundation
import UIKit
import VaultCore
import VaultFeed
import VaultSettings

/// The iOS system pasteboard.
///
/// Publishes when a copy is performed to the pasteboard.
@MainActor
@Observable
public final class Pasteboard {
    private let systemPasteboard: any SystemPasteboard
    private let didPasteSubject = PassthroughSubject<Void, Never>()
    private let localSettings: LocalSettings

    init(_ systemPasteboard: any SystemPasteboard, localSettings: LocalSettings) {
        self.systemPasteboard = systemPasteboard
        self.localSettings = localSettings
    }

    func copy(_ action: VaultTextCopyAction) {
        copy(action.text, as: action.contentType)
    }

    /// Copies `text` following the clipboard settings: cleared after the Clear Clipboard time, and only offered to
    /// the user's other devices if Universal Clipboard is on for this kind of value.
    ///
    /// Every copy Vault makes goes through here, including Copy in the edit menu of selectable text (see
    /// `SelectableText`). The exception is a text field being edited, whose Cut and Copy are the system's.
    func copy(_ text: String, as contentType: PasteboardContentType) {
        let ttl = localSettings.state.pasteTimeToLive.duration
        let localOnly = !localSettings.state.isUniversalClipboardAllowed(for: contentType)
        systemPasteboard.copy(string: text, ttl: ttl, localOnly: localOnly)
        didPasteSubject.send()
    }

    func didPaste() -> AnyPublisher<Void, Never> {
        didPasteSubject.eraseToAnyPublisher()
    }
}
