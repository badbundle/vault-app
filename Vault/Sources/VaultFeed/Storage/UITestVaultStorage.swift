#if DEBUG
import Foundation
import Security

/// Where the app keeps its vault while UI tests run it (`-ui-test-vault`, see `UITestVault` in VaultiOS): a directory,
/// defaults and keychain items of its own, so the tests never read or write the simulator's own vault.
///
/// `VaultSharedStorage` and `VaultIdentifiers.SecureStorageKey.keychainService` hand these out in place of the real
/// ones for the whole run, so every part of the app finds the same vault. A launch that prepares a vault for a test
/// empties them first, so nothing carries over from an earlier test; `-ui-test-vault open` opens the vault the last
/// launch prepared. The extensions are never launched with the argument, so they keep to the real vault.
///
/// Compiled out of release builds.
public struct UITestVaultStorage: Sendable {
    /// The command line argument that runs the app on this storage. It's followed by what to prepare, or `openValue`.
    public static let launchArgument = "-ui-test-vault"
    /// Opens the vault an earlier launch prepared, rather than emptying the storage for a new one.
    public static let openValue = "open"

    /// The storage, if the app was launched for UI tests: emptied the first time it's asked for, unless the launch
    /// opens a vault prepared earlier.
    public static let current: UITestVaultStorage? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: launchArgument) else { return nil }
        let storage = UITestVaultStorage()
        if arguments.dropFirst(index + 1).first != openValue {
            storage.empty()
        }
        storage.makeDirectory()
        return storage
    }()

    /// Stands in for the App Group's container.
    public let directory = FileManager.default.temporaryDirectory
        .appending(path: "ui-test-vault", directoryHint: .isDirectory)
    /// Stands in for the app's standard defaults.
    public let defaultsSuiteName = "com.badbundle.vault.ui-tests"
    /// Stands in for the App Group's defaults.
    public let sharedDefaultsSuiteName = "com.badbundle.vault.ui-tests.shared"
    /// Goes in front of the service of every keychain item, which keeps them apart from the vault's own.
    let keychainServicePrefix = "ui-tests."

    public var defaults: UserDefaults {
        Self.userDefaults(suiteName: defaultsSuiteName)
    }

    public var sharedDefaults: UserDefaults {
        Self.userDefaults(suiteName: sharedDefaultsSuiteName)
    }

    private static func userDefaults(suiteName: String) -> UserDefaults {
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Unable to create the UI test defaults suite '\(suiteName)'")
        }
        return userDefaults
    }

    /// Deletes the vault's files, its defaults and its keychain items, however an earlier test left them.
    private func empty() {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: directory.path(percentEncoded: false)) {
            do {
                try fileManager.removeItem(at: directory)
            } catch {
                fatalError("Unable to empty the UI test vault: \(error)")
            }
        }
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        sharedDefaults.removePersistentDomain(forName: sharedDefaultsSuiteName)
        for key in VaultIdentifiers.SecureStorageKey.allCases {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainServicePrefix + key.rawValue,
                kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
                kSecUseDataProtectionKeychain as String: true,
            ]
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                fatalError("Unable to delete the UI test keychain item '\(key.rawValue)': \(status)")
            }
        }
    }

    private func makeDirectory() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            fatalError("Unable to create the UI test vault: \(error)")
        }
    }
}
#endif
