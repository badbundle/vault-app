import Foundation
import VaultBackup
import VaultCore

/// Encodes an individual `VaultItem` to a `VaultBackupItem` ready for use in the
/// backup and encryption engine.
///
/// This transforms and encodes all the properties of the item such that it's in a format
/// that can be passed to the backup & encryption engine.
final class VaultBackupItemEncoder {
    func encode(storedItem: VaultItem) throws -> VaultBackupItem {
        let itemDetail: VaultBackupItem.Item = switch storedItem.item {
        case let .otpCode(code): .otp(data: encodeOTPCode(code: code))
        case let .secureNote(note): .note(data: encodeNote(note: note))
        case let .encryptedItem(item): .encrypted(data: encodeEncryptedItem(item: item))
        case .recoveryPhrase:
            // Backups only ever carry recovery phrases as encrypted items. Stored items are never in this form, but
            // refuse rather than risk the words ending up in a backup.
            throw VaultItemEncodingError.plaintextRecoveryPhraseNotPersistable
        }
        return VaultBackupItem(
            id: storedItem.id.rawValue,
            createdDate: storedItem.metadata.created,
            updatedDate: storedItem.metadata.updated,
            relativeOrder: storedItem.metadata.relativeOrder,
            userDescription: storedItem.metadata.userDescription,
            tags: storedItem.metadata.tags.reducedToSet(\.id),
            visibility: encodeVisibility(metadata: storedItem.metadata),
            searchableLevel: encodeSearchableLevel(metadata: storedItem.metadata),
            searchPassphraseSalt: storedItem.metadata.searchPassphrase?.salt,
            searchPassphraseDigest: storedItem.metadata.searchPassphrase?.digest,
            killphraseSalt: storedItem.metadata.killphrase?.salt,
            killphraseDigest: storedItem.metadata.killphrase?.digest,
            lockState: encodeLockState(metadata: storedItem.metadata),
            tintColor: encodeTintColor(meta: storedItem.metadata),
            item: itemDetail,
        )
    }
}

// MARK: - Helpers

extension VaultBackupItemEncoder {
    private func encodeTintColor(meta: VaultItem.Metadata) -> VaultBackupRGBColor? {
        guard let color = meta.color else { return nil }
        return .init(red: color.red, green: color.green, blue: color.blue)
    }

    private func encodeVisibility(metadata: VaultItem.Metadata) -> VaultBackupItem.Visibility {
        switch metadata.visibility {
        case .always: .always
        case .onlySearch: .onlySearch
        }
    }

    private func encodeSearchableLevel(metadata: VaultItem.Metadata) -> VaultBackupItem.SearchableLevel {
        switch metadata.searchableLevel {
        case .none: .none
        case .full: .full
        case .onlyTitle: .onlyTitle
        case .onlyPassphrase: .onlyPassphrase
        }
    }

    private func encodeLockState(metadata: VaultItem.Metadata) -> VaultBackupItem.LockState {
        switch metadata.lockState {
        case .notLocked: .notLocked
        case .lockedWithNativeSecurity: .lockedWithNativeSecurity
        }
    }
}

// MARK: - OTP Codes

extension VaultBackupItemEncoder {
    private func encodeOTPCode(code: OTPAuthCode) -> VaultBackupItem.OTP {
        .init(
            secretFormat: encodedSecretFormat(format: code.data.secret.format),
            secretData: code.data.secret.data,
            authType: encodedAuthType(type: code.type),
            period: encodedPeriod(type: code.type),
            counter: encodedCounter(type: code.type),
            algorithm: encodedAlgorithm(algorithm: code.data.algorithm),
            digits: encodedDigits(digits: code.data.digits),
            accountName: code.data.accountName,
            issuer: code.data.issuer,
        )
    }

    private func encodedAuthType(type: OTPAuthType) -> String {
        switch type {
        case .totp: VaultEncodingConstants.OTPAuthType.totp
        case .hotp: VaultEncodingConstants.OTPAuthType.hotp
        }
    }

    private func encodedSecretFormat(format: OTPAuthSecret.Format) -> String {
        switch format {
        case .base32: VaultEncodingConstants.OTPAuthSecret.Format.base32
        }
    }

    private func encodedPeriod(type: OTPAuthType) -> UInt64? {
        switch type {
        case let .totp(period): period
        case .hotp: nil
        }
    }

    private func encodedCounter(type: OTPAuthType) -> UInt64? {
        switch type {
        case let .hotp(counter): counter
        case .totp: nil
        }
    }

    private func encodedDigits(digits: OTPAuthDigits) -> UInt16 {
        digits.value
    }

    private func encodedAlgorithm(algorithm: OTPAuthAlgorithm) -> String {
        switch algorithm {
        case .sha1: VaultEncodingConstants.OTPAuthAlgorithm.sha1
        case .sha256: VaultEncodingConstants.OTPAuthAlgorithm.sha256
        case .sha512: VaultEncodingConstants.OTPAuthAlgorithm.sha512
        }
    }
}

// MARK: - Notes

extension VaultBackupItemEncoder {
    private func encodeNote(note: SecureNote) -> VaultBackupItem.Note {
        .init(title: note.title, rawContents: note.contents, format: encodeFormat(note: note))
    }

    private func encodeFormat(note: SecureNote) -> VaultBackupItem.TextFormat {
        switch note.format {
        case .plain: .plain
        case .markdown: .markdown
        }
    }
}

// MARK: - Encrypted

extension VaultBackupItemEncoder {
    private func encodeEncryptedItem(item: EncryptedItem) -> VaultBackupItem.Encrypted {
        .init(
            version: item.version.stringValue,
            title: item.title,
            data: item.data,
            authentication: item.authentication,
            encryptionIV: item.encryptionIV,
            keygenSalt: item.keygenSalt,
            keygenSignature: item.keygenSignature,
        )
    }
}
