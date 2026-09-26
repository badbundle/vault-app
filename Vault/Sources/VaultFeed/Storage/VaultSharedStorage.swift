import Foundation

/// The on-disk location shared between the main app and all extensions
/// (autofill, widget) that need to read the vault.
///
/// All processes that read or write the vault must resolve the storage
/// directory through this helper so the App Group identifier stays in one
/// place. The widget extension cannot import `VaultiOS` and so must reach
/// the same URL via this lightweight helper.
public enum VaultSharedStorage {
    /// The App Group identifier shared by the main app, autofill extension,
    /// and widget extension. Must match the `com.apple.security.application-groups`
    /// entitlement on every target that reads the vault.
    public static let appGroupID = "group.com.badbundle.vault-group"

    /// Resolves the App Group container URL. Crashes if the entitlement is
    /// missing — there is no meaningful fallback because the vault cannot be
    /// reached without it.
    public static func directory(fileManager: FileManager = .default) -> URL {
        guard let url = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            fatalError("Unable to access App Group container '\(appGroupID)'")
        }
        return url
    }

    /// The App Group's defaults, for settings the extensions read too. Crashes if the entitlement is missing, for
    /// the same reason as `directory(fileManager:)`.
    public static func userDefaults() -> UserDefaults {
        guard let userDefaults = UserDefaults(suiteName: appGroupID) else {
            fatalError("Unable to access the defaults of App Group '\(appGroupID)'")
        }
        return userDefaults
    }
}
