import Foundation

/// How the vault can be opened right now, from the storage state, for what can't recover a change of mode itself: the
/// AutoFill and widget extensions, and the QuickType identity store.
///
/// Read afresh whenever it matters, since the app can change the mode while an extension's process lives on. See
/// "Widgets, AutoFill and QuickType" in `docs/on-device-encryption.md`.
public enum VaultAccessMode: Equatable, Sendable {
    /// The plain store is the vault.
    case plain
    /// The encrypted file is the vault, and the device key opens it: the password is off. Everything works as it does
    /// for a plain vault.
    case deviceKey
    /// The encrypted file is the vault, and only the App Lock Password opens it.
    case password
    /// It can't be opened now: being converted, rekeyed or erased, or the state can't be read.
    case unavailable

    /// - Parameter state: The storage state, or `nil` if it can't be read.
    public init(state: VaultStorageState?) {
        guard let state else {
            self = .unavailable
            return
        }
        switch state.mode {
        case .plain:
            self = state.transition == nil ? .plain : .unavailable
        case .password:
            // Once a conversion has committed, the vault opens with the password, whatever the app still has to tidy
            // up.
            if case .deletingPlainStore = state.transition {
                self = .password
            } else {
                self = state.isSettled ? .password : .unavailable
            }
        case .deviceKey:
            self = state.isSettled ? .deviceKey : .unavailable
        }
    }

    /// As the storage state in `directory` says now.
    public static func current(inDirectory directory: URL) -> VaultAccessMode {
        VaultAccessMode(state: VaultStorageState.current(inDirectory: directory))
    }

    /// Whether it opens without the App Lock Password: a plain vault, or one the device key opens. The widgets,
    /// AutoFill and QuickType work as they always have then.
    public var opensWithoutPassword: Bool {
        switch self {
        case .plain, .deviceKey: true
        case .password, .unavailable: false
        }
    }
}
