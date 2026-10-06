import AppKit
import Security
import Testing

/// The Mac app, launched as it ships, with these tests running inside it.
@MainActor
struct MacAppLaunchTests {
    @Test
    func launch_opensTheMainWindowTitledOnlyVault() async throws {
        let window = try await mainWindow()

        #expect(window.title == "Vault")
    }

    @Test
    func launch_runsInTheAppSandbox() {
        #expect(ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil)
    }

    /// The App Group's container is one the app can write to and read back, as it can only with the group's
    /// entitlement: a container URL alone is given whatever the entitlements.
    @Test
    func appGroupContainer_isTheTeamPrefixedOne() throws {
        let container = try #require(
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID),
        )
        let file = container.appending(path: "vault-app-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }

        try Data("test".utf8).write(to: file)

        #expect(container.lastPathComponent == Self.appGroupID)
        #expect(try Data(contentsOf: file) == Data("test".utf8))
    }

    /// Hide While Recording is on by default (G24, C7), so no window can be captured, and none is restored.
    @Test
    func launch_everyWindowIsHiddenFromCaptureAndNeverRestored() async throws {
        _ = try await mainWindow()

        for window in NSApp.windows where window.isVisible {
            #expect(window.sharingType == .none, "\(window.title)")
            #expect(!window.isRestorable, "\(window.title)")
            #expect(window.tabbingMode == .disallowed, "\(window.title)")
        }
    }

    /// Nothing from Vault is offered to Handoff, the Services menu, URL schemes, documents or AppleScript, and the
    /// app has no way in but its AutoFill extension: no XPC services or login items.
    @Test
    func app_hasNoWayInFromOutside() throws {
        for key in [
            "NSUserActivityTypes", "NSServices", "CFBundleURLTypes", "CFBundleDocumentTypes", "NSAppleScriptEnabled",
            "OSAScriptingDefinition", "UTExportedTypeDeclarations", "UTImportedTypeDeclarations",
        ] {
            #expect(Bundle.main.object(forInfoDictionaryKey: key) == nil, "\(key)")
        }
        #expect(NSApp.servicesProvider == nil)
        let contents = Bundle.main.bundleURL.appending(path: "Contents")
        // Leaving out these tests, which Xcode puts there to run them inside the app.
        let plugIns = try FileManager.default.contentsOfDirectory(atPath: contents.appending(path: "PlugIns").path)
            .filter { !$0.hasSuffix(".xctest") }
        #expect(plugIns == ["VaultMacAutofill.appex"])
        for folder in ["XPCServices", "Library/LoginItems"] {
            #expect(!FileManager.default.fileExists(atPath: contents.appending(path: folder).path), "\(folder)")
        }
    }

    /// The AutoFill extension offers one-time codes and nothing else.
    @Test
    func autofillExtension_providesOneTimeCodesOnly() throws {
        let plugIn = try #require(Bundle(url: Bundle.main.bundleURL.appending(path: "Contents/PlugIns/VaultMacAutofill.appex")))
        let attributes = try #require(
            (plugIn.object(forInfoDictionaryKey: "NSExtension") as? [String: Any])?["NSExtensionAttributes"]
                as? [String: Any],
        )
        let capabilities = try #require(attributes["ASCredentialProviderExtensionCapabilities"] as? [String: Bool])

        #expect(capabilities == [
            "ProvidesOneTimeCodes": true,
            "ProvidesPasskeys": false,
            "ProvidesPasswords": false,
            "ProvidesTextToInsert": false,
            "ShowsConfigurationUI": false,
        ])
    }

    /// docs/mac-app.md, decision 7.
    static let appGroupID = "442P244AFS.com.badbundle.vault"

    /// The main window, once the app has put it on screen.
    private func mainWindow() async throws -> NSWindow {
        for _ in 0 ..< 100 {
            if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true }) {
                return window
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("The main window never opened. Windows: \(NSApp.windows.map(\.title))")
        throw CancellationError()
    }
}

/// The app's keychain, as its entitlements make it: its own group, which its AutoFill extension can't read, by
/// default, and the App Group, which the extension shares (docs/mac-app.md, "Keychain").
@MainActor
struct MacAppKeychainTests {
    nonisolated static let ownGroup = "442P244AFS.com.badbundle.vault.private"

    @Test(arguments: ["442P244AFS.com.badbundle.vault.private", "442P244AFS.com.badbundle.vault"])
    func keychain_eachOfTheAppsGroups_holdsItems(group: String) throws {
        let account = "vault-test-\(UUID().uuidString)"
        defer { SecItemDelete(Self.query(account: account, group: group) as CFDictionary) }
        var item = Self.query(account: account, group: group)
        item[kSecValueData as String] = Data("secret".utf8)
        // Readable while the screen's locked, as validation often runs: this is about the groups, not when.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let added = SecItemAdd(item as CFDictionary, nil)
        #expect(added == errSecSuccess, "SecItemAdd: \(added)")
        var query = Self.query(account: account, group: group)
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        #expect(SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess)
        #expect(result as? Data == Data("secret".utf8))
    }

    /// An item added without a group goes in the app's own, not the App Group.
    @Test
    func keychain_defaultGroup_isTheAppsOwn() throws {
        let account = "vault-test-\(UUID().uuidString)"
        defer { SecItemDelete(Self.query(account: account, group: Self.ownGroup) as CFDictionary) }
        var item = Self.query(account: account, group: nil)
        item[kSecValueData as String] = Data("secret".utf8)
        // Readable while the screen's locked, as validation often runs: this is about the groups, not when.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        item[kSecReturnAttributes as String] = true
        var added: CFTypeRef?

        #expect(SecItemAdd(item as CFDictionary, &added) == errSecSuccess)
        let attributes = try #require(added as? [String: Any])
        #expect(attributes[kSecAttrAccessGroup as String] as? String == Self.ownGroup)
    }

    private static func query(account: String, group: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.badbundle.vault.tests",
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
        if let group {
            query[kSecAttrAccessGroup as String] = group
        }
        return query
    }
}
