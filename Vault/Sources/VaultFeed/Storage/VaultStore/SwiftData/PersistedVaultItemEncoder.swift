import Foundation
import SwiftData
import VaultCore

struct PersistedVaultItemEncoder {
    let context: ModelContext
    let currentDate: () -> Date

    init(context: ModelContext, currentDate: @escaping () -> Date = { Date() }) {
        self.context = context
        self.currentDate = currentDate
    }

    func encode(item: VaultItem.Write, writeUpdateContext: VaultItem.WriteUpdateContext) throws -> PersistedVaultItem {
        try encode(newData: item, writeUpdateContext: writeUpdateContext, existing: nil)
    }

    /// Encodes the given item, inserting it in the encoder's `context`.
    func encode(item: VaultItem.Write, existing: PersistedVaultItem? = nil) throws -> PersistedVaultItem {
        if let existing {
            let writeUpdateContext = VaultItem.WriteUpdateContext(
                id: .init(id: existing.id),
                created: existing.createdDate,
                updated: .updateUpdatedDate,
            )
            return try encode(newData: item, writeUpdateContext: writeUpdateContext, existing: existing)
        } else {
            return try encode(newData: item, writeUpdateContext: nil, existing: nil)
        }
    }
}

// MARK: - Items

extension PersistedVaultItemEncoder {
    private func fetchTagsForItem(newData: VaultItem.Write) throws -> [PersistedVaultTag] {
        let tagsForItemIds = newData.tags.map(\.id).reducedToSet()
        let itemTagsPredicate = #Predicate<PersistedVaultTag> { tagsForItemIds.contains($0.id) }
        return try context.fetch(.init(predicate: itemTagsPredicate))
    }

    private func encode(
        newData: VaultItem.Write,
        writeUpdateContext: VaultItem.WriteUpdateContext?,
        existing: PersistedVaultItem? = nil,
    ) throws -> PersistedVaultItem {
        let now = currentDate()
        let (noteDetails, otpDetails, encryptedItemDetails): (
            PersistedNoteDetails?,
            PersistedOTPDetails?,
            PersistedEncryptedItemDetails?,
        ) = switch newData.item {
        case let .secureNote(note): (encodeSecureNoteDetails(newData: note), nil, nil)
        case let .otpCode(code): (nil, encodeOtpDetails(newData: code), nil)
        case let .encryptedItem(data): (nil, nil, encodeEncryptedItemDetails(newData: data))
        case .recoveryPhrase:
            // Recovery phrases must only ever be persisted encrypted. Refuse before anything is created in the
            // context, so a bug elsewhere can never write the words in plaintext.
            throw VaultItemEncodingError.plaintextRecoveryPhraseNotPersistable
        }
        let updatedDate = switch writeUpdateContext?.updated {
        case .updateUpdatedDate: now
        case let .retainUpdatedDate(date): date
        case nil: now
        }
        let (killphraseSalt, killphraseDigest): (Data?, Data?) = switch newData.killphraseUpdate {
        case .unchanged:
            (existing?.killphraseSalt, existing?.killphraseDigest)
        case .clear:
            (nil, nil)
        case let .set(digest):
            (digest.salt, digest.digest)
        }
        let (searchPassphraseSalt, searchPassphraseDigest): (Data?, Data?) = switch newData.searchPassphraseUpdate {
        case .unchanged:
            (existing?.searchPassphraseSalt, existing?.searchPassphraseDigest)
        case .clear:
            (nil, nil)
        case let .set(digest):
            (digest.salt, digest.digest)
        }
        return try PersistedVaultItem(
            id: writeUpdateContext?.id.id ?? UUID(),
            relativeOrder: newData.relativeOrder,
            createdDate: writeUpdateContext?.created ?? now,
            updatedDate: updatedDate,
            userDescription: newData.userDescription,
            visibility: encodeVisibilityLevel(level: newData.visibility),
            searchableLevel: encodeSearchableLevel(level: newData.searchableLevel),
            searchPassphraseSalt: searchPassphraseSalt,
            searchPassphraseDigest: searchPassphraseDigest,
            killphraseSalt: killphraseSalt,
            killphraseDigest: killphraseDigest,
            lockState: encodeLockState(state: newData.lockState),
            color: newData.color.flatMap { color in
                .init(red: color.red, green: color.green, blue: color.blue)
            },
            showInQuickType: newData.showInQuickType,
            previewMode: newData.previewMode.rawValue,
            tags: fetchTagsForItem(newData: newData),
            noteDetails: noteDetails,
            otpDetails: otpDetails,
            encryptedItemDetails: encryptedItemDetails,
        )
    }

    private func encodeSearchableLevel(level: VaultItemSearchableLevel) -> String {
        switch level {
        case .none: VaultEncodingConstants.SearchableLevel.none
        case .full: VaultEncodingConstants.SearchableLevel.full
        case .onlyTitle: VaultEncodingConstants.SearchableLevel.onlyTitle
        case .onlyPassphrase: VaultEncodingConstants.SearchableLevel.onlyPassphrase
        }
    }

    private func encodeVisibilityLevel(level: VaultItemVisibility) -> String {
        switch level {
        case .always: VaultEncodingConstants.Visibility.always
        case .onlySearch: VaultEncodingConstants.Visibility.onlySearch
        }
    }

    private func encodeLockState(state: VaultItemLockState) -> String {
        switch state {
        case .notLocked: VaultEncodingConstants.LockState.notLocked
        case .lockedWithNativeSecurity: VaultEncodingConstants.LockState.lockedWithNativeSecurity
        }
    }
}

// MARK: - OTP

extension PersistedVaultItemEncoder {
    private func encodeOtpDetails(
        newData: OTPAuthCode,
    ) -> PersistedOTPDetails {
        PersistedOTPDetails(
            accountName: newData.data.accountName,
            issuer: newData.data.issuer,
            algorithm: encodedOTPAlgorithm(newData.data.algorithm),
            authType: encodedOTPAuthType(newData.type),
            counter: encodedOTPCounter(newData.type),
            digits: Int32(newData.data.digits.value),
            period: encodedOTPPeriod(newData.type),
            secretData: newData.data.secret.data,
            secretFormat: encodedOTPSecretFormat(newData.data.secret.format),
        )
    }

    private func encodedOTPAuthType(_ authType: OTPAuthType) -> String {
        switch authType {
        case .totp: VaultEncodingConstants.OTPAuthType.totp
        case .hotp: VaultEncodingConstants.OTPAuthType.hotp
        }
    }

    private func encodedOTPPeriod(_ authType: OTPAuthType) -> Int64? {
        switch authType {
        case let .totp(period): Int64(period)
        case .hotp: nil
        }
    }

    private func encodedOTPCounter(_ authType: OTPAuthType) -> Int64? {
        switch authType {
        case let .hotp(counter): Int64(counter)
        case .totp: nil
        }
    }

    private func encodedOTPAlgorithm(_ algorithm: OTPAuthAlgorithm) -> String {
        switch algorithm {
        case .sha1: VaultEncodingConstants.OTPAuthAlgorithm.sha1
        case .sha256: VaultEncodingConstants.OTPAuthAlgorithm.sha256
        case .sha512: VaultEncodingConstants.OTPAuthAlgorithm.sha512
        }
    }

    private func encodedOTPSecretFormat(_ secretFormat: OTPAuthSecret.Format) -> String {
        switch secretFormat {
        case .base32: VaultEncodingConstants.OTPAuthSecret.Format.base32
        }
    }
}

// MARK: - Note

extension PersistedVaultItemEncoder {
    private func encodeSecureNoteDetails(
        newData: SecureNote,
    ) -> PersistedNoteDetails {
        PersistedNoteDetails(
            title: newData.title,
            contents: newData.contents,
            format: encodeTextFormat(newData.format),
        )
    }

    private func encodeTextFormat(_ format: TextFormat) -> String {
        switch format {
        case .plain: VaultEncodingConstants.TextFormat.plain
        case .markdown: VaultEncodingConstants.TextFormat.markdown
        }
    }
}

// MARK: - Encrypted

extension PersistedVaultItemEncoder {
    private func encodeEncryptedItemDetails(newData: EncryptedItem) -> PersistedEncryptedItemDetails {
        PersistedEncryptedItemDetails(
            version: newData.version.stringValue,
            title: newData.title,
            data: newData.data,
            authentication: newData.authentication,
            encryptionIV: newData.encryptionIV,
            keygenSalt: newData.keygenSalt,
            keygenSignature: newData.keygenSignature,
        )
    }
}
