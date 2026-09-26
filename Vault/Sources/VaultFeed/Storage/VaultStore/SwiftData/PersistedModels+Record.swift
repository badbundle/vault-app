import Foundation

// Copies between the SwiftData models and the plain records every store shares. Each copy is field for field, so
// a record read back from a model it was written to is equal to the original (apart from tag ids that name no
// stored tag, which the store drops).

// MARK: - Items

extension PersistedVaultItem {
    /// A new model holding the record's fields.
    ///
    /// - Parameter tags: The stored tags that `record.tagIDs` name. The caller resolves them, because only it can
    ///   fetch from its context.
    convenience init(record: VaultItemRecord, tags: [PersistedVaultTag]) {
        self.init(
            id: record.id,
            relativeOrder: record.relativeOrder,
            createdDate: record.createdDate,
            updatedDate: record.updatedDate,
            userDescription: record.userDescription,
            visibility: record.visibility,
            searchableLevel: record.searchableLevel,
            searchPassphraseSalt: record.searchPassphraseSalt,
            searchPassphraseDigest: record.searchPassphraseDigest,
            killphraseSalt: record.killphraseSalt,
            killphraseDigest: record.killphraseDigest,
            lockState: record.lockState,
            color: record.color,
            showInQuickType: record.showInQuickType,
            previewMode: record.previewMode,
            tags: tags,
            noteDetails: record.noteDetails.map(PersistedNoteDetails.init(record:)),
            otpDetails: record.otpDetails.map(PersistedOTPDetails.init(record:)),
            encryptedItemDetails: record.encryptedItemDetails.map(PersistedEncryptedItemDetails.init(record:)),
        )
    }

    /// The model's fields as a record.
    func makeRecord() -> VaultItemRecord {
        VaultItemRecord(
            id: id,
            relativeOrder: relativeOrder,
            createdDate: createdDate,
            updatedDate: updatedDate,
            userDescription: userDescription,
            visibility: visibility,
            searchableLevel: searchableLevel,
            searchPassphraseSalt: searchPassphraseSalt,
            searchPassphraseDigest: searchPassphraseDigest,
            killphraseSalt: killphraseSalt,
            killphraseDigest: killphraseDigest,
            lockState: lockState,
            color: color,
            showInQuickType: showInQuickType,
            previewMode: previewMode,
            tagIDs: Set(tags.map(\.id)),
            noteDetails: noteDetails?.makeRecord(),
            otpDetails: otpDetails?.makeRecord(),
            encryptedItemDetails: encryptedItemDetails?.makeRecord(),
        )
    }
}

extension PersistedNoteDetails {
    convenience init(record: VaultItemRecord.NoteDetails) {
        self.init(title: record.title, contents: record.contents, format: record.format)
    }

    func makeRecord() -> VaultItemRecord.NoteDetails {
        VaultItemRecord.NoteDetails(title: title, contents: contents, format: format)
    }
}

extension PersistedOTPDetails {
    convenience init(record: VaultItemRecord.OTPDetails) {
        self.init(
            accountName: record.accountName,
            issuer: record.issuer,
            algorithm: record.algorithm,
            authType: record.authType,
            counter: record.counter,
            digits: record.digits,
            period: record.period,
            secretData: record.secretData,
            secretFormat: record.secretFormat,
        )
    }

    func makeRecord() -> VaultItemRecord.OTPDetails {
        VaultItemRecord.OTPDetails(
            accountName: accountName,
            issuer: issuer,
            algorithm: algorithm,
            authType: authType,
            counter: counter,
            digits: digits,
            period: period,
            secretData: secretData,
            secretFormat: secretFormat,
        )
    }
}

extension PersistedEncryptedItemDetails {
    convenience init(record: VaultItemRecord.EncryptedItemDetails) {
        self.init(
            version: record.version,
            title: record.title,
            data: record.data,
            authentication: record.authentication,
            encryptionIV: record.encryptionIV,
            keygenSalt: record.keygenSalt,
            keygenSignature: record.keygenSignature,
        )
    }

    func makeRecord() -> VaultItemRecord.EncryptedItemDetails {
        VaultItemRecord.EncryptedItemDetails(
            version: version,
            title: title,
            data: data,
            authentication: authentication,
            encryptionIV: encryptionIV,
            keygenSalt: keygenSalt,
            keygenSignature: keygenSignature,
        )
    }
}

// MARK: - Tags

extension PersistedVaultTag {
    /// A new model holding the record's fields, with no items. Items name their tags, not the other way around.
    convenience init(record: VaultTagRecord) {
        self.init(id: record.id, title: record.title, color: record.color, iconName: record.iconName, items: [])
    }

    /// The model's fields as a record.
    func makeRecord() -> VaultTagRecord {
        VaultTagRecord(id: id, title: title, color: color, iconName: iconName)
    }

    /// Updates this model in place to hold the record's fields, keeping its identity and the items that carry it.
    ///
    /// - Precondition: `record.id` is this tag's id.
    func apply(_ record: VaultTagRecord) {
        precondition(record.id == id, "A tag record can only be applied to the tag it describes")
        title = record.title
        color = record.color
        iconName = record.iconName
    }
}
