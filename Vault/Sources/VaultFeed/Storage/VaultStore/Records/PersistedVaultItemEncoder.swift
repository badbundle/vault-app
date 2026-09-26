import Foundation
import VaultCore

/// Encodes a `VaultItem.Write` as the `VaultItemRecord` a store persists.
///
/// This is the one place the persisted encoding of items is decided, so every store writes items the same way.
/// Encoding is pure: storing the record, and resolving its tag ids to stored tags, is the store's job.
struct PersistedVaultItemEncoder {
    let currentDate: () -> Date

    init(currentDate: @escaping () -> Date = { Date() }) {
        self.currentDate = currentDate
    }

    /// Encodes an item whose id and dates are already known, as when importing.
    func encode(item: VaultItem.Write, writeUpdateContext: VaultItem.WriteUpdateContext) throws -> VaultItemRecord {
        try encode(newData: item, writeUpdateContext: writeUpdateContext, existing: nil)
    }

    /// Encodes a new item, or an update to the `existing` one.
    ///
    /// An update keeps the existing item's id and created date, moves its updated date to now, and keeps its
    /// killphrase and search passphrase digests where the write leaves them `.unchanged`.
    func encode(item: VaultItem.Write, existing: VaultItemRecord? = nil) throws -> VaultItemRecord {
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
    private func encode(
        newData: VaultItem.Write,
        writeUpdateContext: VaultItem.WriteUpdateContext?,
        existing: VaultItemRecord? = nil,
    ) throws -> VaultItemRecord {
        let now = currentDate()
        let (noteDetails, otpDetails, encryptedItemDetails): (
            VaultItemRecord.NoteDetails?,
            VaultItemRecord.OTPDetails?,
            VaultItemRecord.EncryptedItemDetails?,
        ) = switch newData.item {
        case let .secureNote(note): (encodeSecureNoteDetails(newData: note), nil, nil)
        case let .otpCode(code): (nil, encodeOtpDetails(newData: code), nil)
        case let .encryptedItem(data): (nil, nil, encodeEncryptedItemDetails(newData: data))
        case .recoveryPhrase:
            // Recovery phrases must only ever be persisted encrypted. Refuse before any record exists, so a bug
            // elsewhere can never write the words in plaintext.
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
        return VaultItemRecord(
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
            tagIDs: newData.tags.map(\.id).reducedToSet(),
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
    ) -> VaultItemRecord.OTPDetails {
        VaultItemRecord.OTPDetails(
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
    ) -> VaultItemRecord.NoteDetails {
        VaultItemRecord.NoteDetails(
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
    private func encodeEncryptedItemDetails(newData: EncryptedItem) -> VaultItemRecord.EncryptedItemDetails {
        VaultItemRecord.EncryptedItemDetails(
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
