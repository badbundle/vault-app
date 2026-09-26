import Foundation
import FoundationExtensions
import VaultCore

/// Local settings for the codes.
@MainActor
public struct LocalSettingsState {
    @DefaultsStored public var pasteTimeToLive: PasteTTL

    /// When `true`, OTP copies are allowed to sync via iCloud Universal Clipboard.
    @DefaultsStored public var allowUniversalClipboardForOTPs: Bool

    init(defaults: Defaults) {
        _pasteTimeToLive = DefaultsStored(
            defaults: defaults,
            defaultsKey: .init(VaultIdentifiers.Preferences.General.settingsPasteTTL),
            defaultValue: .default,
        )
        _allowUniversalClipboardForOTPs = DefaultsStored(
            defaults: defaults,
            defaultsKey: .init(VaultIdentifiers.Preferences.UniversalClipboard.allowOTPs),
            defaultValue: false,
        )
    }

    /// Returns `true` if values of the given content type may be synced to Universal Clipboard.
    public func isUniversalClipboardAllowed(for contentType: PasteboardContentType) -> Bool {
        switch contentType {
        case .otp: allowUniversalClipboardForOTPs
        }
    }

    /// Returns `true` if values of any content type may be synced to Universal Clipboard.
    public var isUniversalClipboardAllowedForAny: Bool {
        PasteboardContentType.allCases.contains(where: isUniversalClipboardAllowed(for:))
    }
}
