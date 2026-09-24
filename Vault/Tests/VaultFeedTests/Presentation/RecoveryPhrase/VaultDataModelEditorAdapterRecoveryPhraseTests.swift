import Foundation
import FoundationExtensions
import TestHelpers
import Testing
import VaultCore
import VaultKeygen
@testable import VaultFeed

@MainActor
struct VaultDataModelEditorAdapterRecoveryPhraseTests {
    @Test
    func createRecoveryPhrase_insertsEncryptedItemWithNewPassword() async throws {
        let store = VaultStoreStub()
        let dataModel = anyVaultDataModel(vaultStore: store, vaultTagStore: VaultTagStoreStub())
        let sut = makeSUT(dataModel: dataModel)
        var edits = anyEdits()
        edits.newEncryptionPassword = "new password"

        try await confirmation("Insert handler called") { confirmation in
            store.insertHandler = { data in
                defer { confirmation() }
                #expect(data.userDescription == "", "Nothing about the phrase is stored outside the encrypted item")
                #expect(data.lockState == .lockedWithNativeSecurity)
                #expect(data.showInQuickType == false)
                #expect(data.previewMode == .hidden)
                #expect(data.visibility == .always)
                guard case let .encryptedItem(item) = data.item else {
                    Issue.record("Recovery phrase was not encrypted")
                    return .new()
                }
                #expect(item.title == "My wallet")
                let decrypted = try? decrypt(item, password: "new password")
                #expect(decrypted == RecoveryPhrase(
                    title: "My wallet",
                    words: validBIP39Words,
                    standard: .bip39,
                    passphrase: " my passphrase ",
                ))
                return .new()
            }

            try await sut.createRecoveryPhrase(initialEdits: edits)
        }
    }

    @Test
    func createRecoveryPhrase_throwsWithoutPasswordAndNeverWrites() async throws {
        let store = VaultStoreStub()
        store.insertHandler = { _ in
            Issue.record("Should never write an unencrypted recovery phrase")
            return .new()
        }
        let sut = makeSUT(dataModel: anyVaultDataModel(vaultStore: store, vaultTagStore: VaultTagStoreStub()))

        await #expect(throws: VaultDataModelEditorAdapter.RecoveryPhraseError.missingEncryptionKey) {
            try await sut.createRecoveryPhrase(initialEdits: anyEdits())
        }
    }

    @Test
    func createRecoveryPhrase_savesCanonicalSpellingOfValidPhrase() async throws {
        let store = VaultStoreStub()
        let sut = makeSUT(dataModel: anyVaultDataModel(vaultStore: store, vaultTagStore: VaultTagStoreStub()))
        var edits = anyEdits()
        edits.applyInput(" ABANDON ", at: 0)
        edits.newEncryptionPassword = "pass"

        try await confirmation("Insert handler called") { confirmation in
            store.insertHandler = { data in
                defer { confirmation() }
                guard case let .encryptedItem(item) = data.item else {
                    Issue.record("Recovery phrase was not encrypted")
                    return .new()
                }
                let decrypted = try? decrypt(item, password: "pass")
                #expect(decrypted?.words == validBIP39Words)
                return .new()
            }

            try await sut.createRecoveryPhrase(initialEdits: edits)
        }
    }

    @Test
    func updateRecoveryPhrase_reencryptsWithExistingKey() async throws {
        let store = VaultStoreStub()
        let sut = makeSUT(dataModel: anyVaultDataModel(vaultStore: store, vaultTagStore: VaultTagStoreStub()))
        let existingKey = try VaultKeyDeriver.testing.createEncryptionKey(password: "existing")
        var edits = anyEdits()
        edits.existingEncryptionKey = existingKey
        let id = Identifier<VaultItem>.new()

        let returnedKey = try await confirmation("Update handler called") { confirmation in
            store.updateHandler = { actualID, data in
                defer { confirmation() }
                #expect(actualID == id)
                #expect(data.lockState == .lockedWithNativeSecurity)
                guard case let .encryptedItem(item) = data.item else {
                    Issue.record("Recovery phrase was not encrypted")
                    return
                }
                #expect(item.keygenSalt == existingKey.salt)
                #expect((try? decrypt(item, password: "existing"))?.words == validBIP39Words)
            }

            return try await sut.updateRecoveryPhrase(id: id, edits: edits)
        }

        #expect(returnedKey == existingKey)
    }

    @Test
    func updateRecoveryPhrase_newPasswordReplacesExistingKey() async throws {
        let store = VaultStoreStub()
        let sut = makeSUT(dataModel: anyVaultDataModel(vaultStore: store, vaultTagStore: VaultTagStoreStub()))
        let existingKey = try VaultKeyDeriver.testing.createEncryptionKey(password: "existing")
        var edits = anyEdits()
        edits.existingEncryptionKey = existingKey
        edits.newEncryptionPassword = "changed"

        let returnedKey = try await confirmation("Update handler called") { confirmation in
            store.updateHandler = { _, data in
                defer { confirmation() }
                guard case let .encryptedItem(item) = data.item else {
                    Issue.record("Recovery phrase was not encrypted")
                    return
                }
                #expect(item.keygenSalt != existingKey.salt)
                #expect((try? decrypt(item, password: "changed"))?.words == validBIP39Words)
                #expect((try? decrypt(item, password: "existing")) == nil)
            }

            return try await sut.updateRecoveryPhrase(id: .new(), edits: edits)
        }

        #expect(returnedKey != existingKey)
    }

    @Test
    func updateRecoveryPhrase_neverShowsContentInPreview() async throws {
        let store = VaultStoreStub()
        let sut = makeSUT(dataModel: anyVaultDataModel(vaultStore: store, vaultTagStore: VaultTagStoreStub()))
        var edits = anyEdits()
        edits.existingEncryptionKey = try VaultKeyDeriver.testing.createEncryptionKey(password: "existing")
        edits.previewMode = .titleAndFirstLine

        try await confirmation("Update handler called") { confirmation in
            store.updateHandler = { _, data in
                defer { confirmation() }
                #expect(data.previewMode == .titleOnly)
            }

            _ = try await sut.updateRecoveryPhrase(id: .new(), edits: edits)
        }
    }

    @Test
    func updateRecoveryPhrase_propagatesFailureOnError() async throws {
        let store = VaultStoreErroring(error: TestError())
        let sut = makeSUT(dataModel: anyVaultDataModel(vaultStore: store, vaultTagStore: store))
        var edits = anyEdits()
        edits.existingEncryptionKey = try VaultKeyDeriver.testing.createEncryptionKey(password: "existing")

        await #expect(throws: (any Error).self) {
            try await sut.updateRecoveryPhrase(id: .new(), edits: edits)
        }
    }

    @Test
    func deleteRecoveryPhrase_deletesFromFeed() async throws {
        let store = VaultStoreStub()
        let sut = makeSUT(dataModel: anyVaultDataModel(vaultStore: store, vaultTagStore: VaultTagStoreStub()))
        let id = Identifier<VaultItem>.new()

        try await confirmation("Delete handler called") { confirmation in
            store.deleteHandler = { actualID in
                defer { confirmation() }
                #expect(actualID == id)
            }

            try await sut.deleteRecoveryPhrase(id: id)
        }
    }
}

// MARK: - Helpers

extension VaultDataModelEditorAdapterRecoveryPhraseTests {
    private func makeSUT(dataModel: VaultDataModel) -> VaultDataModelEditorAdapter {
        let keyDeriverFactory = VaultKeyDeriverFactoryMock()
        keyDeriverFactory.makeVaultItemKeyDeriverHandler = { .testing }
        return VaultDataModelEditorAdapter(dataModel: dataModel, keyDeriverFactory: keyDeriverFactory)
    }

    private func anyEdits() -> RecoveryPhraseDetailEdits {
        var edits = RecoveryPhraseDetailEdits.new()
        edits.title = "My wallet"
        edits.setWordCount(12)
        for (index, word) in validBIP39Words.enumerated() {
            edits.applyInput(word, at: index)
        }
        edits.seedPassphrase = " my passphrase "
        return edits
    }

    private func decrypt(_ item: EncryptedItem, password: String) throws -> RecoveryPhrase {
        let key = try VaultKeyDeriver.testing.recreateEncryptionKey(password: password, salt: item.keygenSalt)
        return try VaultItemDecryptor(key: key).decrypt(
            item: item,
            expectedItemIdentifier: VaultIdentifiers.Item.recoveryPhrase,
        )
    }
}
