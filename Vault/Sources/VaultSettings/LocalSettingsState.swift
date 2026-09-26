import Foundation
import FoundationExtensions
import VaultCore

/// Local settings for the codes.
@MainActor
public struct LocalSettingsState {
    /// Kept in the defaults the app shares with its extensions, so a code copied from a widget is cleared on time too.
    @DefaultsStored public var pasteTimeToLive: PasteTTL

    /// When `true`, OTP copies are allowed to sync via iCloud Universal Clipboard.
    @DefaultsStored public var allowUniversalClipboardForOTPs: Bool
    /// When `true`, text copied from notes is allowed to sync via iCloud Universal Clipboard.
    @DefaultsStored public var allowUniversalClipboardForNotes: Bool

    /// When `true`, the whole app is covered while the screen is recorded, mirrored or shared. On by default
    /// (MANIFESTO C7). Recovery phrases hide then whatever this says.
    @DefaultsStored public var hidesVaultWhileScreenCaptured: Bool

    /// When `true`, new codes and notes start locked. Only read when an item is created.
    @DefaultsStored public var lockNewItems: Bool
    /// When `true`, new codes start out offered in QuickType. Only read when a code is created.
    @DefaultsStored public var showNewCodesInQuickType: Bool

    /// What tapping a code in the feed does.
    @DefaultsStored public var codeTapAction: CodeTapAction

    /// When `true`, a time-based code shows the code after it during the last seconds of its countdown. Off by
    /// default.
    @DefaultsStored public var showsNextCode: Bool

    init(defaults: Defaults, sharedDefaults: Defaults) {
        Self.move(PasteTTL.storageKey, from: defaults, to: sharedDefaults)
        _codeTapAction = DefaultsStored(
            defaults: defaults,
            defaultsKey: .init(VaultIdentifiers.Preferences.General.codeTapAction),
            defaultValue: .default,
        )
        _showsNextCode = DefaultsStored(
            defaults: defaults,
            defaultsKey: .init(VaultIdentifiers.Preferences.General.showsNextCode),
            defaultValue: false,
        )
        _pasteTimeToLive = DefaultsStored(
            defaults: sharedDefaults,
            defaultsKey: PasteTTL.storageKey,
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
        _allowUniversalClipboardForNotes = DefaultsStored(
            defaults: defaults,
            defaultsKey: .init(VaultIdentifiers.Preferences.UniversalClipboard.allowNotes),
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

    /// Moves a value earlier versions kept in the app's own defaults to the shared ones, so a choice the user made
    /// before it moved is kept. Only a choice is ever stored, so there's nothing to move for someone who never made
    /// one, and they keep getting the default.
    private static func move(_ key: Key<some Codable>, from defaults: Defaults, to sharedDefaults: Defaults) {
        guard defaults !== sharedDefaults, !sharedDefaults.has(key), let value = defaults.get(for: key) else { return }
        do {
            try sharedDefaults.set(value, for: key)
            defaults.clear(key)
        } catch {
            // Left where it was, to try again next time.
        }
    }

    /// The kinds of copied value Universal Clipboard can be turned on for, in the order Settings shows them.
    ///
    /// Details copied from a page, such as a code's description, always stay on this device.
    public static let universalClipboardContentTypes: [PasteboardContentType] = [.otp, .note]

    /// Returns `true` if values of the given content type may be synced to Universal Clipboard.
    public func isUniversalClipboardAllowed(for contentType: PasteboardContentType) -> Bool {
        switch contentType {
        case .otp: allowUniversalClipboardForOTPs
        case .note: allowUniversalClipboardForNotes
        case .detail: false
        }
    }

    /// What Universal Clipboard is on for, summed up.
    public var universalClipboardSummary: UniversalClipboardSummary {
        let allowed = Self.universalClipboardContentTypes.filter(isUniversalClipboardAllowed(for:))
        if allowed.isEmpty {
            return .off
        } else if allowed.count == Self.universalClipboardContentTypes.count {
            return .on
        } else {
            return .only(allowed)
        }
    }
}

/// What Universal Clipboard is on for, as the Settings row that opens it sums it up.
public enum UniversalClipboardSummary: Equatable, Sendable {
    /// Nothing copied can reach other devices.
    case off
    /// Every kind of value it can be turned on for can reach other devices.
    case on
    /// Only these kinds of value can reach other devices.
    case only([PasteboardContentType])
}
