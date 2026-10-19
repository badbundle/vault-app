import Foundation
import FoundationExtensions
import VaultCore
import VaultKeygen

/// Encapsulates editing state for a private key.
///
/// Like a recovery phrase, a private key is always encrypted and always locked, so there's no way to turn either off:
/// the edits are only valid once there's a password, and the lock state is fixed.
public struct PrivateKeyDetailEdits: DetailEditorEditableState {
    public var relativeOrder: UInt64

    /// Stored in plaintext, alongside the encrypted item.
    public var title: String

    /// Freeform description shown below the title, encrypted along with the key.
    public var contents: String

    /// The key, as entered.
    public var key: String

    public var viewConfig: VaultItemViewConfiguration

    /// Plaintext entered by the user when setting or replacing the search
    /// passphrase. Always blank on screen-open. Sent to the digester and
    /// then discarded before persistence.
    @FieldValidated(validationLogic: .stringRequiringContent)
    public var searchPassphrase: String = ""

    /// Whether this item already has a stored search-passphrase digest.
    public var hasExistingSearchPassphrase: Bool = false

    /// Whether this item currently has, or should have, a killphrase set.
    public var killphraseEnabled: Bool = false

    /// Plaintext entered by the user when setting or replacing the
    /// killphrase. Always blank on screen-open.
    public var newKillphrase: String = ""

    /// Set when the user has chosen a new password. A key will be derived from it, replacing `existingEncryptionKey`.
    public var newEncryptionPassword: String = ""

    /// The key the item is currently encrypted with, used to re-encrypt it when there's no new password.
    public var existingEncryptionKey: DerivedEncryptionKey?

    public var color: VaultItemColor?

    public var tags: Set<Identifier<VaultItemTag>>

    public var previewMode: NotePreviewMode

    public init(
        title: String,
        contents: String,
        key: String,
        color: VaultItemColor?,
        viewConfig: VaultItemViewConfiguration,
        searchPassphrase: String,
        hasExistingSearchPassphrase: Bool,
        killphraseEnabled: Bool,
        newKillphrase: String,
        tags: Set<Identifier<VaultItemTag>>,
        relativeOrder: UInt64,
        existingEncryptionKey: DerivedEncryptionKey?,
        previewMode: NotePreviewMode,
    ) {
        self.title = title
        self.contents = contents
        self.key = key
        self.color = color
        self.viewConfig = viewConfig
        self.searchPassphrase = searchPassphrase
        self.hasExistingSearchPassphrase = hasExistingSearchPassphrase
        self.killphraseEnabled = killphraseEnabled
        self.newKillphrase = newKillphrase
        self.tags = tags
        self.relativeOrder = relativeOrder
        self.existingEncryptionKey = existingEncryptionKey
        self.previewMode = previewMode
    }

    public var isValid: Bool {
        DetailEditorStep.allCases.allSatisfy(isComplete)
    }

    public func isComplete(_ step: DetailEditorStep) -> Bool {
        switch step {
        case .content: hasKey
        case .details, .appearance: true
        case .security: isEncrypted && isSearchPassphraseValid && isKillphraseValid
        }
    }

    /// Private keys are always locked, this can't be changed.
    public var lockState: VaultItemLockState {
        .lockedWithNativeSecurity
    }

    /// Something has been entered as the key.
    ///
    /// This doesn't mean that it's valid: a key Vault doesn't recognize, or one that doesn't validate, can still be
    /// saved.
    public var hasKey: Bool {
        key.isNotBlank
    }

    /// The format the key is recognized as, and whether it's valid.
    public var validation: PrivateKeyValidation {
        PrivateKeyValidator.validate(key)
    }

    public var isSearchPassphraseValid: Bool {
        switch viewConfig {
        case .requiresSearchPassphrase: hasExistingSearchPassphrase || $searchPassphrase.isValid
        default: true
        }
    }

    public var isKillphraseValid: Bool {
        // Blank entry is valid (means "keep existing" when enabled, or
        // "no killphrase" when disabled). Whitespace-only is rejected.
        newKillphrase.isEmpty || newKillphrase.isNotBlank
    }

    public var killphraseEnabledText: String {
        killphraseEnabled ? "Enabled" : "None"
    }

    public var isEncrypted: Bool {
        newEncryptionPassword.isNotBlank || existingEncryptionKey.isNotNil
    }

    public var passwordState: PasswordState {
        if newEncryptionPassword.isNotBlank {
            existingEncryptionKey == nil ? .set : .willChange
        } else {
            existingEncryptionKey == nil ? .required : .set
        }
    }

    public enum PasswordState: Equatable, Sendable {
        /// No password yet, so the item can't be saved.
        case required
        case set
        /// The item will be re-encrypted with a new password when saved.
        case willChange
    }
}

// MARK: - Saving

extension PrivateKeyDetailEdits {
    /// The key to save.
    public func makePrivateKey() -> PrivateKey {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return PrivateKey(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            // A single-line key that's only valid without the whitespace inside it is saved without it, as that's
            // the form a wallet will accept.
            key: validation.canonicalKey ?? trimmedKey,
            contents: contents.trimmingCharacters(in: .whitespacesAndNewlines),
        )
    }
}

// MARK: - Helpers

extension PrivateKeyDetailEdits {
    /// Create a `PrivateKeyDetailEdits` in a blank state with initial input values, for creation.
    public static func new() -> PrivateKeyDetailEdits {
        .init(
            title: "",
            contents: "",
            key: "",
            color: nil,
            viewConfig: .alwaysVisible,
            searchPassphrase: "",
            hasExistingSearchPassphrase: false,
            killphraseEnabled: false,
            newKillphrase: "",
            tags: [],
            relativeOrder: .min,
            existingEncryptionKey: nil,
            // Only the title: the contents of an encrypted item are never previewed.
            previewMode: .titleOnly,
        )
    }
}
