import Foundation

/// What an App Lock Password has to be.
///
/// Anyone with a copy of the encrypted vault can guess at its password on their own computers, as fast as the key
/// derivation allows, with no delay and no erase to stop them ("Residual limits" in `docs/on-device-encryption.md`).
/// A six-digit PIN would fall in about half an hour, so it has to be a real password.
public enum AppLockPasswordRules {
    /// The fewest characters a password can have.
    public static let minimumLength = 8

    /// A rule a password breaks.
    public enum Problem: Equatable, Sendable {
        /// Fewer than `minimumLength` characters.
        case tooShort
        /// Nothing but numbers (and spaces), like a PIN.
        case onlyNumbers
    }

    /// The first rule `password` breaks, or `nil` if it can be used.
    public static func problem(with password: String) -> Problem? {
        if password.count < minimumLength {
            .tooShort
        } else if password.allSatisfy({ $0.isNumber || $0.isWhitespace }) {
            .onlyNumbers
        } else {
            nil
        }
    }
}
