import Foundation
import FoundationExtensions

extension Defaults {
    /// Creates non-persistent defaults in a unique domain to allow for use by parallel tests.
    public static func nonPersistent() throws -> Defaults {
        try Defaults(userDefaults: .nonPersistent())
    }
}

extension UserDefaults {
    enum NonPersistentError: Error {
        case cannotCreateUserDefaults
    }

    /// Creates `UserDefaults` in a unique, empty domain to allow for use by parallel tests.
    public static func nonPersistent() throws -> UserDefaults {
        let suite = Data.random(count: 32).base64EncodedString()
        guard let userDefaults = UserDefaults(suiteName: suite) else {
            throw NonPersistentError.cannotCreateUserDefaults
        }
        userDefaults.removePersistentDomain(forName: suite)
        return userDefaults
    }
}
