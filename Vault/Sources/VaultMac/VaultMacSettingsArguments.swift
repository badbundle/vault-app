import Foundation

/// Keeps Vault's own settings out of reach of launch arguments.
///
/// On the Mac, an app's launch arguments go into a defaults domain of their own, which every defaults read in the
/// process checks first, the App Group's included. Vault's settings are only ever changed in Settings, so they're taken
/// out of that domain, by their `vault.` prefix, before anything reads them. Other arguments, such as the language,
/// stay.
enum VaultMacSettingsArguments {
    static let prefix = "vault."

    static func removeVaultSettings(from defaults: UserDefaults = .standard) {
        let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        let kept = arguments.filter { !$0.key.hasPrefix(prefix) }
        guard kept.count != arguments.count else { return }
        defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain)
        defaults.setVolatileDomain(kept, forName: UserDefaults.argumentDomain)
    }
}
