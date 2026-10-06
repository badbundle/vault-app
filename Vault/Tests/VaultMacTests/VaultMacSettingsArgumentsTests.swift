import Foundation
import Testing
import VaultCore
@testable import VaultMac

/// Launch arguments can't set Vault's own settings.
@Suite(.serialized)
struct VaultMacSettingsArgumentsTests {
    @Test
    func removeVaultSettings_takesVaultsSettingsOutOfTheArgumentsOnly() throws {
        let defaults = UserDefaults.standard
        let original = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defer {
            defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain)
            defaults.setVolatileDomain(original, forName: UserDefaults.argumentDomain)
        }
        let key = VaultIdentifiers.Preferences.AppLock.erasesAfterFailedPasswords
        var arguments = original
        arguments[key] = "NO"
        arguments["AppleLanguages"] = ["en"]
        defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain)
        defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        let appGroup = try #require(UserDefaults(suiteName: "vault-settings-arguments-tests-\(UUID().uuidString)"))
        #expect(appGroup.object(forKey: key) != nil)

        VaultMacSettingsArguments.removeVaultSettings(from: defaults)

        #expect(appGroup.object(forKey: key) == nil)
        #expect(defaults.object(forKey: key) == nil)
        #expect(defaults.volatileDomain(forName: UserDefaults.argumentDomain)["AppleLanguages"] != nil)
    }
}
