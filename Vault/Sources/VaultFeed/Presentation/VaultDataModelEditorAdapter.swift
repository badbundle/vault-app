import Foundation
import FoundationExtensions
import VaultCore
import VaultKeygen

@MainActor
public struct VaultDataModelEditorAdapter {
    private let dataModel: VaultDataModel
    private let keyDeriverFactory: any VaultKeyDeriverFactory

    public init(dataModel: VaultDataModel, keyDeriverFactory: any VaultKeyDeriverFactory) {
        self.dataModel = dataModel
        self.keyDeriverFactory = keyDeriverFactory
    }

    /// Translate the UI's killphrase edit state into a `KillphraseUpdate`
    /// that the storage layer can apply.
    ///
    /// - If the toggle is off → `.clear` (remove any existing digest).
    /// - If the toggle is on **and** the user typed a new phrase → derive a
    ///   fresh digest and emit `.set(...)`. Refusing to digest a blank
    ///   string preserves the existing "only non-blank phrases are armed"
    ///   semantics.
    /// - If the toggle is on **and** the field is blank → `.unchanged`,
    ///   meaning the existing digest (if any) is kept. This is the path
    ///   that handles the "user opened the edit screen without changing
    ///   anything" case, since the UI can no longer hydrate the original
    ///   plaintext into the field.
    private func killphraseUpdate(enabled: Bool, newPhrase: String) -> VaultItem.KillphraseUpdate {
        guard enabled else { return .clear }
        let trimmed = newPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isNotEmpty else { return .unchanged }
        guard let digester = dataModel.killphraseDigester else {
            // Digester not available (extremely unexpected: setup() has
            // not run, or keychain unreachable). Treat as "leave existing
            // alone" rather than silently clearing or storing plaintext.
            return .unchanged
        }
        return .set(digester.makeDigest(phrase: trimmed))
    }

    /// Translate the UI's search-passphrase edit state into a
    /// `SearchPassphraseUpdate` that the storage layer can apply.
    ///
    /// - If the item is not configured to require a passphrase →
    ///   `.clear` (remove any existing digest).
    /// - If it requires a passphrase **and** the user typed a new one →
    ///   derive a fresh digest and emit `.set(...)`. Trimming follows the
    ///   killphrase pattern: whitespace-only is treated as no input.
    /// - If it requires a passphrase **and** the field is blank →
    ///   `.unchanged`. The existing digest (if any) is kept; this is the
    ///   path taken when the user opens the edit screen without changing
    ///   the passphrase, since the UI no longer hydrates plaintext.
    private func searchPassphraseUpdate(
        viewConfig: VaultItemViewConfiguration,
        newPhrase: String,
    ) -> VaultItem.SearchPassphraseUpdate {
        guard viewConfig == .requiresSearchPassphrase else { return .clear }
        let trimmed = newPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isNotEmpty else { return .unchanged }
        guard let digester = dataModel.searchPassphraseDigester else {
            return .unchanged
        }
        return .set(digester.makeDigest(phrase: trimmed))
    }
}

extension VaultDataModelEditorAdapter: OTPCodeDetailEditor {
    public func createCode(initialEdits: OTPCodeDetailEdits) async throws {
        let newCodeVaultItem = try VaultItem.Write(
            relativeOrder: initialEdits.relativeOrder,
            userDescription: initialEdits.description,
            color: initialEdits.color,
            item: .otpCode(initialEdits.asOTPAuthCode()),
            tags: initialEdits.tags,
            visibility: initialEdits.viewConfig.visibility,
            searchableLevel: initialEdits.viewConfig.searchableLevel,
            searchPassphraseUpdate: searchPassphraseUpdate(
                viewConfig: initialEdits.viewConfig,
                newPhrase: initialEdits.searchPassphrase,
            ),
            killphraseUpdate: killphraseUpdate(
                enabled: initialEdits.killphraseEnabled,
                newPhrase: initialEdits.newKillphrase,
            ),
            lockState: initialEdits.lockState,
            showInQuickType: initialEdits.showInQuickType,
            previewMode: .titleAndFirstLine,
        )

        try await dataModel.insert(item: newCodeVaultItem)
    }

    public func updateCode(id: Identifier<VaultItem>, item: OTPAuthCode, edits: OTPCodeDetailEdits) async throws {
        var item = item
        item.data.accountName = edits.accountNameTitle
        item.data.issuer = edits.issuerTitle

        try await dataModel.update(
            itemID: id,
            data: .init(
                relativeOrder: edits.relativeOrder,
                userDescription: edits.description,
                color: edits.color,
                item: .otpCode(item),
                tags: edits.tags,
                visibility: edits.viewConfig.visibility,
                searchableLevel: edits.viewConfig.searchableLevel,
                searchPassphraseUpdate: searchPassphraseUpdate(
                    viewConfig: edits.viewConfig,
                    newPhrase: edits.searchPassphrase,
                ),
                killphraseUpdate: killphraseUpdate(
                    enabled: edits.killphraseEnabled,
                    newPhrase: edits.newKillphrase,
                ),
                lockState: edits.lockState,
                showInQuickType: edits.showInQuickType,
                previewMode: .titleAndFirstLine,
            ),
        )
    }

    public func deleteCode(id: Identifier<VaultItem>) async throws {
        try await dataModel.delete(itemID: id)
    }
}

extension VaultDataModelEditorAdapter: SecureNoteDetailEditor {
    public func createNote(initialEdits: SecureNoteDetailEdits) async throws {
        let newItem = try await makeNoteItem(edits: initialEdits)
        let newVaultItem = VaultItem.Write(
            relativeOrder: initialEdits.relativeOrder,
            userDescription: initialEdits.contentPreviewLine,
            color: initialEdits.color,
            item: newItem,
            tags: initialEdits.tags,
            visibility: initialEdits.viewConfig.visibility,
            searchableLevel: initialEdits.viewConfig.searchableLevel,
            searchPassphraseUpdate: searchPassphraseUpdate(
                viewConfig: initialEdits.viewConfig,
                newPhrase: initialEdits.searchPassphrase,
            ),
            killphraseUpdate: killphraseUpdate(
                enabled: initialEdits.killphraseEnabled,
                newPhrase: initialEdits.newKillphrase,
            ),
            lockState: initialEdits.lockState,
            showInQuickType: false,
            previewMode: initialEdits.previewMode,
        )

        try await dataModel.insert(item: newVaultItem)
    }

    public func updateNote(id: Identifier<VaultItem>, item _: SecureNote, edits: SecureNoteDetailEdits) async throws {
        let updatedItem = try await makeNoteItem(edits: edits)
        let updatedVaultItem = VaultItem.Write(
            relativeOrder: edits.relativeOrder,
            userDescription: edits.contentPreviewLine,
            color: edits.color,
            item: updatedItem,
            tags: edits.tags,
            visibility: edits.viewConfig.visibility,
            searchableLevel: edits.viewConfig.searchableLevel,
            searchPassphraseUpdate: searchPassphraseUpdate(
                viewConfig: edits.viewConfig,
                newPhrase: edits.searchPassphrase,
            ),
            killphraseUpdate: killphraseUpdate(
                enabled: edits.killphraseEnabled,
                newPhrase: edits.newKillphrase,
            ),
            lockState: edits.lockState,
            showInQuickType: false,
            previewMode: edits.previewMode,
        )

        try await dataModel.update(itemID: id, data: updatedVaultItem)
    }

    private func makeNoteItem(edits: SecureNoteDetailEdits) async throws -> VaultItem.Payload {
        let note = SecureNote(
            title: edits.titleLine,
            contents: edits.contents,
            format: edits.textFormat,
        )
        if edits.newEncryptionPassword.isNotBlank {
            // An explicit new encryption password has been specified.
            // Derive the key and encrypt the item.
            let keyDervier = keyDeriverFactory.makeVaultItemKeyDeriver()
            let encryptionKey = try await Task.background {
                try keyDervier.createEncryptionKey(password: edits.newEncryptionPassword)
            }
            let encryptor = VaultItemEncryptor(key: encryptionKey)
            let encryptedNote = try await Task.background {
                try encryptor.encrypt(item: note)
            }
            return .encryptedItem(encryptedNote)
        } else if let encryptionKey = edits.existingEncryptionKey {
            // Use the existing encryption key, as the user does not want to override the existing one.
            let encryptor = VaultItemEncryptor(key: encryptionKey)
            let encryptedNote = try await Task.background {
                try encryptor.encrypt(item: note)
            }
            return .encryptedItem(encryptedNote)
        } else {
            // No encryption is specified or should be used for this item.
            return .secureNote(note)
        }
    }

    public func deleteNote(id: Identifier<VaultItem>) async throws {
        try await dataModel.delete(itemID: id)
    }
}

extension VaultDataModelEditorAdapter: RecoveryPhraseDetailEditor {
    public enum RecoveryPhraseError: Error, Sendable {
        /// Recovery phrases can only be saved encrypted, but there was no password or key to encrypt it with.
        case missingEncryptionKey
    }

    public func createRecoveryPhrase(initialEdits: RecoveryPhraseDetailEdits) async throws {
        let (encryptedItem, _) = try await encryptRecoveryPhrase(edits: initialEdits)
        try await dataModel.insert(item: makeRecoveryPhraseWrite(encryptedItem: encryptedItem, edits: initialEdits))
    }

    public func updateRecoveryPhrase(
        id: Identifier<VaultItem>,
        edits: RecoveryPhraseDetailEdits,
    ) async throws -> DerivedEncryptionKey {
        let (encryptedItem, key) = try await encryptRecoveryPhrase(edits: edits)
        try await dataModel.update(
            itemID: id,
            data: makeRecoveryPhraseWrite(encryptedItem: encryptedItem, edits: edits),
        )
        return key
    }

    public func deleteRecoveryPhrase(id: Identifier<VaultItem>) async throws {
        try await dataModel.delete(itemID: id)
    }

    /// Recovery phrases are always stored encrypted, so this only ever produces an `EncryptedItem`, never a
    /// plaintext payload, and fails if there's nothing to encrypt it with.
    private func encryptRecoveryPhrase(
        edits: RecoveryPhraseDetailEdits,
    ) async throws -> (EncryptedItem, DerivedEncryptionKey) {
        let encryptionKey: DerivedEncryptionKey
        if edits.newEncryptionPassword.isNotBlank {
            let keyDeriver = keyDeriverFactory.makeVaultItemKeyDeriver()
            encryptionKey = try await Task.background {
                try keyDeriver.createEncryptionKey(password: edits.newEncryptionPassword)
            }
        } else if let existingEncryptionKey = edits.existingEncryptionKey {
            encryptionKey = existingEncryptionKey
        } else {
            throw RecoveryPhraseError.missingEncryptionKey
        }
        let phrase = edits.makeRecoveryPhrase()
        let encryptor = VaultItemEncryptor(key: encryptionKey)
        let encryptedItem = try await Task.background {
            try encryptor.encrypt(item: phrase)
        }
        return (encryptedItem, encryptionKey)
    }

    private func makeRecoveryPhraseWrite(
        encryptedItem: EncryptedItem,
        edits: RecoveryPhraseDetailEdits,
    ) -> VaultItem.Write {
        VaultItem.Write(
            relativeOrder: edits.relativeOrder,
            // Nothing about the phrase is stored outside of the encrypted item, except the title.
            userDescription: "",
            color: edits.color,
            item: .encryptedItem(encryptedItem),
            tags: edits.tags,
            visibility: edits.viewConfig.visibility,
            searchableLevel: edits.viewConfig.searchableLevel,
            searchPassphraseUpdate: searchPassphraseUpdate(
                viewConfig: edits.viewConfig,
                newPhrase: edits.searchPassphrase,
            ),
            killphraseUpdate: killphraseUpdate(
                enabled: edits.killphraseEnabled,
                newPhrase: edits.newKillphrase,
            ),
            lockState: .lockedWithNativeSecurity,
            showInQuickType: false,
            // Encrypted items never show a preview of their contents.
            previewMode: edits.previewMode == .titleAndFirstLine ? .titleOnly : edits.previewMode,
        )
    }
}
