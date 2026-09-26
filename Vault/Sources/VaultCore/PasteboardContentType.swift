import Foundation

/// Classifies the sensitivity of a value being copied to the system pasteboard.
///
/// Used to decide per-type whether the value may be synced to iCloud Universal Clipboard. Only add a case once
/// something in the app copies that kind of value, so every Universal Clipboard setting has an effect.
public enum PasteboardContentType: String, Sendable, Equatable, Hashable, CaseIterable, Codable {
    /// A short-lived one-time code (TOTP/HOTP).
    case otp
}
