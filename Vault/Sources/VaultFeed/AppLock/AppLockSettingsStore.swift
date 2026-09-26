import Foundation

/// The app lock's settings, kept in the defaults the app shares with its extensions.
///
/// The AutoFill and widget extensions read them too: while the lock is on, neither shows a code until the user has
/// authenticated. Only the app changes them, through `AppLockService`.
///
/// `UserDefaults` is documented thread-safe, and this only reads and writes single values through it. Marked
/// `@unchecked Sendable` so the widget extension's actor can hold it.
public struct AppLockSettingsStore: @unchecked Sendable { // swiftlint:disable:this no_unchecked_sendable
    private let userDefaults: UserDefaults

    public init(userDefaults: UserDefaults) {
        self.userDefaults = userDefaults
    }

    /// The App Group's defaults, which the app and every extension read.
    public static func shared() -> AppLockSettingsStore {
        AppLockSettingsStore(userDefaults: VaultSharedStorage.userDefaults())
    }

    /// Whether the app asks for device authentication before it shows the vault. Off until the user turns it on.
    public var isEnabled: Bool {
        get {
            userDefaults.bool(forKey: VaultIdentifiers.Preferences.AppLock.isEnabled)
        }
        nonmutating set {
            userDefaults.set(newValue, forKey: VaultIdentifiers.Preferences.AppLock.isEnabled)
        }
    }

    /// How long the app can be in the background before it locks. Immediately unless the user has chosen otherwise,
    /// and immediately for any value this version doesn't know.
    public var delay: AppLockDelay {
        get {
            AppLockDelay(rawValue: userDefaults.integer(forKey: VaultIdentifiers.Preferences.AppLock.delay)) ?? .default
        }
        nonmutating set {
            userDefaults.set(newValue.rawValue, forKey: VaultIdentifiers.Preferences.AppLock.delay)
        }
    }
}
