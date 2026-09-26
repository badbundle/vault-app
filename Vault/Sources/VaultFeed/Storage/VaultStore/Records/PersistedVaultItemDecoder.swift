import Foundation
import FoundationExtensions
import VaultCore

/// Decodes a stored `VaultItemRecord` into a `VaultItem`.
///
/// The counterpart of `PersistedVaultItemEncoder`, shared by every store. It throws for a record it can't make
/// sense of, and stores report that as a retrieval error for the item.
struct PersistedVaultItemDecoder {
    func decode(record: VaultItemRecord) throws -> VaultItem {
        let metadata = try VaultItem.Metadata(
            id: Identifier(id: record.id),
            created: record.createdDate,
            updated: record.updatedDate,
            relativeOrder: record.relativeOrder,
            userDescription: record.userDescription,
            tags: decodeTags(ids: record.tagIDs),
            visibility: decodeVisibility(level: record.visibility),
            searchableLevel: decodeSearchableLevel(level: record.searchableLevel),
            searchPassphrase: decodeSearchPassphrase(record: record),
            killphrase: decodeKillphrase(record: record),
            lockState: decodeLockState(value: record.lockState),
            color: decodeColor(record: record),
            showInQuickType: record.showInQuickType,
            previewMode: NotePreviewMode(rawValue: record.previewMode) ?? .titleAndFirstLine,
        )
        if let otp = record.otpDetails {
            let otpCode = try decodeOTPCode(otp: otp)
            return VaultItem(metadata: metadata, item: .otpCode(otpCode))
        } else if let note = record.noteDetails {
            let note = try SecureNote(
                title: note.title,
                contents: note.contents,
                format: decodeTextFormat(value: note.format),
            )
            return VaultItem(metadata: metadata, item: .secureNote(note))
        } else if let encryptedItem = record.encryptedItemDetails {
            let encrypted = try decodeEncryptedItem(details: encryptedItem)
            return VaultItem(metadata: metadata, item: .encryptedItem(encrypted))
        } else {
            throw VaultItemDecodingError.missingItemDetail
        }
    }
}

// MARK: - Helpers

extension PersistedVaultItemDecoder {
    private func decodeTags(ids: Set<UUID>) -> Set<Identifier<VaultItemTag>> {
        ids.map {
            Identifier<VaultItemTag>(id: $0)
        }.reducedToSet()
    }

    private func decodeSearchableLevel(level: String) throws(VaultItemDecodingError) -> VaultItemSearchableLevel {
        switch level {
        case VaultEncodingConstants.SearchableLevel.full: .full
        case VaultEncodingConstants.SearchableLevel.none: .none
        case VaultEncodingConstants.SearchableLevel.onlyTitle: .onlyTitle
        case VaultEncodingConstants.SearchableLevel.onlyPassphrase: .onlyPassphrase
        default: throw VaultItemDecodingError.invalidSearchableLevel
        }
    }

    private func decodeVisibility(level: String) throws(VaultItemDecodingError) -> VaultItemVisibility {
        switch level {
        case VaultEncodingConstants.Visibility.always: .always
        case VaultEncodingConstants.Visibility.onlySearch: .onlySearch
        default: throw VaultItemDecodingError.invalidVisibility
        }
    }

    private func decodeKillphrase(record: VaultItemRecord) -> KillphraseDigest? {
        guard let salt = record.killphraseSalt, let digest = record.killphraseDigest else { return nil }
        return KillphraseDigest(salt: salt, digest: digest)
    }

    private func decodeSearchPassphrase(record: VaultItemRecord) -> SearchPassphraseDigest? {
        guard let salt = record.searchPassphraseSalt, let digest = record.searchPassphraseDigest else { return nil }
        return SearchPassphraseDigest(salt: salt, digest: digest)
    }

    private func decodeColor(record: VaultItemRecord) -> VaultItemColor? {
        if let color = record.color {
            VaultItemColor(red: color.red, green: color.green, blue: color.blue)
        } else {
            nil
        }
    }

    private func decodeOTPCode(otp: VaultItemRecord.OTPDetails) throws(VaultItemDecodingError) -> OTPAuthCode {
        try OTPAuthCode(
            type: decodeOTPType(otp: otp),
            data: .init(
                secret: .init(data: otp.secretData, format: decodeSecretFormat(value: otp.secretFormat)),
                algorithm: decodeAlgorithm(value: otp.algorithm),
                digits: decode(digits: otp.digits),
                accountName: otp.accountName,
                issuer: otp.issuer,
            ),
        )
    }

    private func decodeOTPType(otp: VaultItemRecord.OTPDetails) throws(VaultItemDecodingError) -> OTPAuthType {
        switch otp.authType {
        case VaultEncodingConstants.OTPAuthType.totp:
            guard let period = otp.period else {
                throw VaultItemDecodingError.missingPeriodForTOTP
            }
            return .totp(period: UInt64(period))
        case VaultEncodingConstants.OTPAuthType.hotp:
            guard let counter = otp.counter else {
                throw VaultItemDecodingError.missingCounterForHOTP
            }
            return .hotp(counter: UInt64(counter))
        default:
            throw VaultItemDecodingError.invalidOTPType
        }
    }

    private func decode(digits: Int32) throws(VaultItemDecodingError) -> OTPAuthDigits {
        guard (Int32(UInt16.min) ... Int32(UInt16.max)).contains(digits) else {
            throw VaultItemDecodingError.invalidNumberOfDigits
        }
        return OTPAuthDigits(value: UInt16(digits))
    }

    private func decodeAlgorithm(value: String) throws(VaultItemDecodingError) -> OTPAuthAlgorithm {
        switch value {
        case VaultEncodingConstants.OTPAuthAlgorithm.sha1: .sha1
        case VaultEncodingConstants.OTPAuthAlgorithm.sha256: .sha256
        case VaultEncodingConstants.OTPAuthAlgorithm.sha512: .sha512
        default: throw VaultItemDecodingError.invalidAlgorithm
        }
    }

    private func decodeSecretFormat(value: String) throws(VaultItemDecodingError) -> OTPAuthSecret.Format {
        switch value {
        case VaultEncodingConstants.OTPAuthSecret.Format.base32: .base32
        default: throw VaultItemDecodingError.invalidSecretFormat
        }
    }

    private func decodeLockState(value: String?) throws(VaultItemDecodingError) -> VaultItemLockState {
        switch value {
        case VaultEncodingConstants.LockState.notLocked: .notLocked
        case VaultEncodingConstants.LockState.lockedWithNativeSecurity: .lockedWithNativeSecurity
        case nil: .notLocked
        default: throw VaultItemDecodingError.invalidLockState
        }
    }

    private func decodeTextFormat(value: String) throws(VaultItemDecodingError) -> TextFormat {
        switch value {
        case VaultEncodingConstants.TextFormat.plain: .plain
        case VaultEncodingConstants.TextFormat.markdown: .markdown
        default: throw VaultItemDecodingError.invalidTextFormat
        }
    }

    private func decodeEncryptedItem(
        details: VaultItemRecord.EncryptedItemDetails,
    ) throws(SemVer.ParseError) -> EncryptedItem {
        try .init(
            version: SemVer(string: details.version),
            title: details.title,
            data: details.data,
            authentication: details.authentication,
            encryptionIV: details.encryptionIV,
            keygenSalt: details.keygenSalt,
            keygenSignature: details.keygenSignature,
        )
    }
}
