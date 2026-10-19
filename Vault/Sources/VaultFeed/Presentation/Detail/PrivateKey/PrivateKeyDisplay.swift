import Foundation
import VaultCore

extension PrivateKey {
    /// `key` as it's shown on screen: able to wrap between any two of its characters, and never hyphenated.
    ///
    /// Text wraps a long word by hyphenating it, which would show a key with a hyphen in it that isn't part of it,
    /// for someone to copy out by hand. A zero-width space between each character makes each its own word, so a line
    /// can end anywhere without one. It's only ever drawn: what's stored, and what VoiceOver reads, is the key itself.
    public static func displayText(for key: String) -> String {
        key.map(String.init).joined(separator: "\u{200B}")
    }
}
