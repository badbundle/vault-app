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
    /// app has no way in but its AutoFill extension: no XPC services or login items. Its widget extension only reads
    /// the codes the app hands it (G98).
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
        #expect(plugIns.sorted() == ["VaultMacAutofill.appex", "VaultMacWidgets.appex"])
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

    /// The widget extension is a widget extension, and nothing else.
    @Test
    func widgetExtension_isOnlyWidgets() throws {
        let plugIn = try #require(
            Bundle(url: Bundle.main.bundleURL.appending(path: "Contents/PlugIns/VaultMacWidgets.appex")),
        )
        let attributes = try #require(plugIn.object(forInfoDictionaryKey: "NSExtension") as? [String: Any])

        #expect(attributes as NSDictionary == ["NSExtensionPointIdentifier": "com.apple.widgetkit-extension"])
    }

    /// The widget extension has no App Group, which would also make it a member of the App Group's keychain access
    /// group, and so able to read the device key. Its only keychain access group is the widgets' own: not the one the
    /// app shares with AutoFill, which holds the attempt counter and the wrap stamp (G84, G98, G99).
    @Test
    func widgetExtension_hasNoAppGroupAndOnlyTheWidgetsKeychainGroup() throws {
        let entitlements = try Self.signedEntitlements(ofPlugIn: "VaultMacWidgets.appex")

        #expect(entitlements["com.apple.security.application-groups"] == nil)
        #expect(entitlements["keychain-access-groups"] as? [String] == ["442P244AFS.com.badbundle.vault.widgets"])
        #expect(entitlements["com.apple.security.app-sandbox"] as? Bool == true)
    }

    /// The AutoFill extension has the App Group, for the vault, and the keychain access group it shares with the app,
    /// for the attempt counter, the wrap stamp and the app lock's settings, and no other (G84, G99).
    @Test
    func autofillExtension_hasTheAppGroupAndTheSharedKeychainGroup() throws {
        let entitlements = try Self.signedEntitlements(ofPlugIn: "VaultMacAutofill.appex")

        #expect(entitlements["com.apple.security.application-groups"] as? [String] == [Self.appGroupID])
        #expect(entitlements["keychain-access-groups"] as? [String] == [Self.appGroupID, Self.sharedKeychainGroupID])
        #expect(entitlements["com.apple.security.app-sandbox"] as? Bool == true)
    }

    /// The only App Intents are the widget's, which the app lists as it does any extension's, and none is offered to
    /// Shortcuts or Spotlight (docs/mac-app.md, decision 2).
    @Test
    func appIntents_areOnlyTheWidgetsAndNoneIsOfferedOutsideIt() throws {
        let metadata = Bundle.main.bundleURL
            .appending(path: "Contents/Resources/Metadata.appintents/extract.actionsdata")
        let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: metadata)) as? [String: Any])
        let actions = try #require(json["actions"] as? [String: [String: Any]])

        #expect(Set(actions.keys) == ["OTPWidgetIntent", "CopyTOTPCodeIntent", "IncrementAndCopyHOTPCodeIntent"])
        for (name, action) in actions {
            #expect(action["isDiscoverable"] as? Bool == false, "\(name)")
        }
    }

    /// docs/mac-app.md, decision 7.
    static let appGroupID = "442P244AFS.com.badbundle.vault"
    /// The keychain access group the app shares with its AutoFill extension only (docs/mac-app.md, "Keychain").
    static let sharedKeychainGroupID = "442P244AFS.com.badbundle.vault.shared"

    /// The entitlements a plug-in in the app is signed with.
    private static func signedEntitlements(ofPlugIn name: String) throws -> [String: Any] {
        let url = Bundle.main.bundleURL.appending(path: "Contents/PlugIns/\(name)")
        var staticCode: SecStaticCode?
        #expect(SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess)
        var information: CFDictionary?
        #expect(SecCodeCopySigningInformation(
            try #require(staticCode),
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information,
        ) == errSecSuccess)
        let signing = try #require(information as? [String: Any])
        return try #require(signing[kSecCodeInfoEntitlementsDict as String] as? [String: Any])
    }

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

/// The app's keychain, as its entitlements make it: its own group, which its extensions can't read, by default, the
/// App Group and the group it shares with the AutoFill extension, which only that extension shares too, and the
/// widgets' group, which only the widget extension shares (docs/mac-app.md, "Keychain").
@MainActor
struct MacAppKeychainTests {
    nonisolated static let ownGroup = "442P244AFS.com.badbundle.vault.private"

    @Test(arguments: [
        "442P244AFS.com.badbundle.vault.private",
        "442P244AFS.com.badbundle.vault",
        "442P244AFS.com.badbundle.vault.shared",
        "442P244AFS.com.badbundle.vault.widgets",
    ])
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

    /// The same item in the App Group's group and the shared one is two items, read, written and deleted apart: what
    /// moving the attempt counter, the wrap stamp and the app lock's settings out of the App Group's group relies on
    /// (G99).
    @Test
    func keychain_theSameItemInTheAppGroupAndTheSharedGroup_isTwoItems() throws {
        let account = "vault-test-\(UUID().uuidString)"
        let groups = [MacAppLaunchTests.appGroupID, MacAppLaunchTests.sharedKeychainGroupID]
        defer {
            for group in groups {
                SecItemDelete(Self.query(account: account, group: group) as CFDictionary)
            }
        }
        for group in groups {
            var item = Self.query(account: account, group: group)
            item[kSecValueData as String] = Data(group.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            #expect(added == errSecSuccess, "SecItemAdd in \(group): \(added)")
        }
        // Adding it to a group that has it already finds it there, as a move that's already been made does.
        var again = Self.query(account: account, group: MacAppLaunchTests.sharedKeychainGroupID)
        again[kSecValueData as String] = Data("again".utf8)
        #expect(SecItemAdd(again as CFDictionary, nil) == errSecDuplicateItem)

        #expect(SecItemDelete(Self.query(account: account, group: MacAppLaunchTests.appGroupID) as CFDictionary)
            == errSecSuccess)

        var query = Self.query(account: account, group: MacAppLaunchTests.sharedKeychainGroupID)
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        #expect(SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess)
        #expect(result as? Data == Data(MacAppLaunchTests.sharedKeychainGroupID.utf8))
        var gone = Self.query(account: account, group: MacAppLaunchTests.appGroupID)
        gone[kSecReturnData as String] = true
        #expect(SecItemCopyMatching(gone as CFDictionary, &result) == errSecItemNotFound)
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
