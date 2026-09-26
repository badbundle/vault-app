#if canImport(UIKit)
import Foundation
import UIKit

/// Puts a value Vault copies on the system pasteboard the same way wherever it's copied from, in the app or its
/// widget: marked concealed so clipboard managers don't show it, kept to this device unless it's allowed on
/// Universal Clipboard, and cleared when Clear Clipboard says.
///
/// Lives in `VaultiOSShared` so the widget extension copies exactly as the app does.
public enum ConcealedPasteboard {
    /// Widely-supported clipboard-manager UTI for marking copied values as concealed (passwords / OTPs).
    /// Honoured by tools like Paste, Maccy, etc. so the copied value is not shown in clipboard previews.
    static let concealedTypeIdentifier = "org.nspasteboard.ConcealedType"

    /// Copies `string`, replacing whatever was on the pasteboard.
    ///
    /// - Parameters:
    ///   - expiresAt: When the pasteboard clears it, or `nil` to keep it.
    ///   - localOnly: When `true`, it isn't offered to the user's other devices over Universal Clipboard.
    public static func copy(
        _ string: String,
        expiresAt: Date?,
        localOnly: Bool,
        to pasteboard: UIPasteboard = .general,
    ) {
        pasteboard.setItems(items(for: string), options: options(expiresAt: expiresAt, localOnly: localOnly))
    }

    static func items(for string: String) -> [[String: Any]] {
        [[
            UIPasteboard.typeAutomatic: string,
            concealedTypeIdentifier: string,
        ]]
    }

    static func options(expiresAt: Date?, localOnly: Bool) -> [UIPasteboard.OptionsKey: Any] {
        var options: [UIPasteboard.OptionsKey: Any] = [.localOnly: localOnly]
        if let expiresAt {
            options[.expirationDate] = expiresAt
        }
        return options
    }
}
#endif
