import AppKit
import SwiftUI
import TestHelpers
import Testing
import VaultCore
import VaultSettings
@testable import VaultFeed
@testable import VaultMac

@MainActor
struct VaultMacEditorSnapshotTests {
    @Test(arguments: MacAppearance.allCases)
    func newCode(appearance: MacAppearance) throws {
        let view = try sheet(.newCode)

        assertSnapshot(
            of: view,
            as: .macWindow(width: 520, height: 620, appearance: appearance.name),
            named: appearance.rawValue,
        )
    }

    @Test
    func newNote() throws {
        let view = try sheet(.newNote)

        assertSnapshot(of: view, as: .macWindow(width: 560, height: 680))
    }

    /// Each word is typed into a secure field, so none shows as it's typed.
    @Test
    func newRecoveryPhrase() throws {
        let view = try sheet(.newRecoveryPhrase)

        assertSnapshot(of: view, as: .macWindow(width: 560, height: 720))
    }

    /// An existing item's editor can delete it, after asking (C6).
    @Test
    func editCode() throws {
        let item = MacTestItems.code(issuer: "Example", account: "ada@example.com")
        let code = try #require(item.item.otpCode)
        let view = try sheet(.editCode(code, item.metadata))

        assertSnapshot(of: view, as: .macWindow(width: 520, height: 620))
    }

    @Test
    func editNote() throws {
        let item = MacTestItems.note(title: "Wi-Fi", contents: "Wi-Fi\nThe router's password is under the stand.")
        let note = try #require(item.item.secureNote)
        let view = try sheet(.editNote(note, item.metadata, nil))

        assertSnapshot(of: view, as: .macWindow(width: 560, height: 680))
    }

    /// Its words are never shown while it's edited.
    @Test
    func editRecoveryPhrase() throws {
        let phrase = RecoveryPhrase(
            title: "Wallet",
            words: [
                "abandon",
                "ability",
                "able",
                "about",
                "above",
                "absent",
                "absorb",
                "abstract",
                "absurd",
                "abuse",
                "access",
                "accident",
            ],
            standard: .bip39,
            passphrase: "",
            contents: "",
        )
        let key = DerivedEncryptionKey(key: .zero(), salt: Data(), keyDervier: .testing)
        let view = try sheet(.editRecoveryPhrase(phrase, MacTestItems.metadata(), key))

        assertSnapshot(of: view, as: .macWindow(width: 560, height: 720))
    }

    private func sheet(_ request: VaultMacEditorRequest) throws -> some View {
        let (dataModel, _) = try MacTestVault.make()
        return try VaultMacEditorSheet(
            request: request,
            dataModel: dataModel,
            keyDeriverFactory: VaultKeyDeriverFactoryImpl(),
            localSettings: LocalSettings(defaults: .nonPersistent()),
            close: {},
        )
    }
}
