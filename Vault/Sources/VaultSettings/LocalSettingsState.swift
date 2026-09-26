import Foundation
import FoundationExtensions
import VaultCore

/// Local settings for the codes.
@MainActor
public struct LocalSettingsState {
    @DefaultsStored public var pasteTimeToLive: PasteTTL

    /// When `true`, OTP copies are allowed to sync via iCloud Universal Clipboard.
    @DefaultsStored public var allowUniversalClipboardForOTPs: Bool

    /// When `true`, the whole app is covered while the screen is recorded, mirrored or shared. On by default
    /// (MANIFESTO C7). Recovery phrases hide then whatever this says.
    @DefaultsStored public var hidesVaultWhileScreenCaptured: Bool

    /// When `true`, new codes and notes start locked. Only read when an item is created.
    @DefaultsStored public var lockNewItems: Bool
    /// When `true`, new codes start out offered in QuickType. Only read when a code is created.
    @DefaultsStored public var showNewCodesInQuickType: Bool

    init(defaults: Defaults) {
        _pasteTimeToLive = DefaultsStored(
            defaults: defaults,
            defaultsKey: .init(VaultIdentifiers.Preferences.General.settingsPasteTTL),
            defaultValue: .default,
        )
        _hidesVaultWhileScreenCaptured = DefaultsStored(
            defaults: defaults,
            defaultsKey: .init(VaultIdentifiers.Preferences.General.hideWhileScreenCaptured),
            defaultValue: true,
        )
        _allowUniversalClipboardForOTPs = DefaultsStored(
            defaults: defaults,
            defaultsKey: .init(VaultIdentifiers.Preferences.UniversalClipboard.allowOTPs),
            defaultValue: false,
        )
        _lockNewItems = DefaultsStored(
            defaults: defaults,
            defaultsKey: .init(VaultIdentifiers.Preferences.NewItems.lock),
            defaultValue: false,
        )
        // Off, so a code is only offered to AutoFill once the user chooses (MANIFESTO C7).
        _showNewCodesInQuickType = DefaultsStored(
            defaults: defaults,
            defaultsKey: .init(VaultIdentifiers.Preferences.NewItems.showCodesInQuickType),
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
