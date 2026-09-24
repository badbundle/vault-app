import Foundation
import VaultCore

public struct VaultItemDemoFactory {
    public init() {}

    public func makeTOTPCode() -> VaultItem.Write {
        let randomAccountName = "mcky.dev \(UUID().uuidString.prefix(10))"
        let code = OTPAuthCode(
            type: .totp(period: 30),
            data: .init(secret: .empty(), accountName: randomAccountName, issuer: "mcky.dev"),
        )
        return VaultItem.Write(
            relativeOrder: 0,
            userDescription: "This is a demo TOTP code",
            color: nil,
            item: .otpCode(code),
            tags: [],
            visibility: .always,
            searchableLevel: .full,
            searchPassphraseUpdate: .clear,
            killphraseUpdate: .clear,
            lockState: .notLocked,
            showInQuickType: true,
            previewMode: .titleAndFirstLine,
        )
    }

    public func makeHOTPCode() -> VaultItem.Write {
        let randomAccountName = "example.com \(UUID().uuidString.prefix(10))"
        let code = OTPAuthCode(
            type: .totp(period: 30),
            data: .init(secret: .empty(), accountName: randomAccountName, issuer: "mcky.dev"),
        )
        return VaultItem.Write(
            relativeOrder: 0,
            userDescription: "This is a demo HOTP code",
            color: nil,
            item: .otpCode(code),
            tags: [],
            visibility: .always,
            searchableLevel: .full,
            searchPassphraseUpdate: .clear,
            killphraseUpdate: .clear,
            lockState: .notLocked,
            showInQuickType: true,
            previewMode: .titleAndFirstLine,
        )
    }

    public func makeSecureNote() -> VaultItem.Write {
        let note = SecureNote(
            title: "Hi there",
            contents: "This is a test \(UUID().uuidString.prefix(12))",
            format: .plain,
        )
        return VaultItem.Write(
            relativeOrder: 0,
            userDescription: "This is a demo note",
            color: nil,
            item: .secureNote(note),
            tags: [],
            visibility: .always,
            searchableLevel: .full,
            searchPassphraseUpdate: .clear,
            killphraseUpdate: .clear,
            lockState: .notLocked,
            showInQuickType: false,
            previewMode: .titleAndFirstLine,
        )
    }

    public func makeEncryptedSecureNote() throws -> VaultItem.Write {
        let note = SecureNote(
            title: "Hi there",
            contents: "This is a test \(UUID().uuidString.prefix(12))",
            format: .plain,
        )
        let derived = try VaultKeyDeriver.Item.Fast.v1.createEncryptionKey(password: "hello")
        let encryptor = VaultItemEncryptor(key: derived)
        let encrypted = try encryptor.encrypt(item: note)
        return VaultItem.Write(
            relativeOrder: 0,
            userDescription: note.title,
            color: nil,
            item: .encryptedItem(encrypted),
            tags: [],
            visibility: .always,
            searchableLevel: .full,
            searchPassphraseUpdate: .clear,
            killphraseUpdate: .clear,
            lockState: .notLocked,
            showInQuickType: false,
            previewMode: .titleAndFirstLine,
        )
    }

    /// A recovery phrase (the public BIP39 test vector), encrypted with the password "hello".
    public func makeEncryptedRecoveryPhrase() throws -> VaultItem.Write {
        let phrase = RecoveryPhrase(
            title: "Demo wallet \(UUID().uuidString.prefix(6))",
            words: Array(repeating: "abandon", count: 11) + ["about"],
            standard: .bip39,
            passphrase: "",
        )
        let derived = try VaultKeyDeriver.Item.Fast.v1.createEncryptionKey(password: "hello")
        let encryptor = VaultItemEncryptor(key: derived)
        let encrypted = try encryptor.encrypt(item: phrase)
        return VaultItem.Write(
            relativeOrder: 0,
            userDescription: "",
            color: nil,
            item: .encryptedItem(encrypted),
            tags: [],
            visibility: .always,
            searchableLevel: .full,
            searchPassphraseUpdate: .clear,
            killphraseUpdate: .clear,
            lockState: .lockedWithNativeSecurity,
            showInQuickType: false,
            previewMode: .hidden,
        )
    }
}
