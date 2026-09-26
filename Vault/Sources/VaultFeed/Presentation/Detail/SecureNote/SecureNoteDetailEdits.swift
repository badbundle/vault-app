import Foundation
import FoundationExtensions
import VaultCore
import VaultKeygen

/// Encapsulates editing state for a given note.
///
/// This is a partial edit, which will be merged with the current model to form an update.
public struct SecureNoteDetailEdits: DetailEditorEditableState {
    public var relativeOrder: UInt64

    @FieldValidated(validationLogic: .alwaysValid)
    public var contents: String = ""

    public var viewConfig: VaultItemViewConfiguration

    /// Plaintext entered by the user when setting or replacing the search
    /// passphrase. Always blank on screen-open. Sent to the digester and
    /// then discarded before persistence.
    @FieldValidated(validationLogic: .stringRequiringContent)
    public var searchPassphrase: String = ""

    /// Whether this item already has a stored search-passphrase digest.
    /// Lets the edit form treat a blank `searchPassphrase` field as "keep
    /// the existing value" rather than "clear it", mirroring the
    /// killphrase behavior. The plaintext is never surfaced.
    public var hasExistingSearchPassphrase: Bool = false

    /// Whether this item currently has, or should have, a killphrase set.
    /// The plaintext killphrase is never surfaced to the UI; this is the
    /// only handle the edit screen has on the existing state.
    public var killphraseEnabled: Bool = false

    /// Plaintext entered by the user when setting or replacing the
    /// killphrase. Always blank on screen-open. Sent to the digester and
    /// then discarded before persistence.
    public var newKillphrase: String = ""

    /// This will only be set if the user is updating the encryption password for the item.
    ///
    /// A non-empty string implies that the encryption key should be recreated by deriving a key from this password.
    /// This will override any existing key set via `existingEncryptionKey`.
    public var newEncryptionPassword: String = ""

    /// This will only be set if the item is encrypted and already has an existing key set.
    ///
    /// If there is no password in `newEncryptionPassword`, this will be used to re-encrypt the item.
    public var existingEncryptionKey: DerivedEncryptionKey?

    public var color: VaultItemColor?

    public var tags: Set<Identifier<VaultItemTag>>

    public var textFormat: TextFormat

    public var lockState: VaultItemLockState

    public var previewMode: NotePreviewMode

    public init(
        contents: String,
        textFormat: TextFormat,
        color: VaultItemColor?,
        viewConfig: VaultItemViewConfiguration,
        searchPassphrase: String,
        hasExistingSearchPassphrase: Bool,
        killphraseEnabled: Bool,
        newKillphrase: String,
        tags: Set<Identifier<VaultItemTag>>,
        lockState: VaultItemLockState,
        relativeOrder: UInt64,
        existingEncryptionKey: DerivedEncryptionKey?,
        previewMode: NotePreviewMode,
    ) {
        self.contents = contents
        self.textFormat = textFormat
        self.color = color
        self.viewConfig = viewConfig
        self.searchPassphrase = searchPassphrase
        self.hasExistingSearchPassphrase = hasExistingSearchPassphrase
        self.killphraseEnabled = killphraseEnabled
        self.newKillphrase = newKillphrase
        self.tags = tags
        self.lockState = lockState
        self.relativeOrder = relativeOrder
        self.existingEncryptionKey = existingEncryptionKey
        self.previewMode = previewMode
    }

    public var isValid: Bool {
        DetailEditorStep.allCases.allSatisfy(isComplete)
    }

    public func isComplete(_ step: DetailEditorStep) -> Bool {
        switch step {
        case .content: $contents.isValid
        case .details, .appearance: true
        case .security: isPassphraseValid && isKillphraseValid
        }
    }

    public var isPassphraseValid: Bool {
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

    public var killphraseIsEnabled: Bool {
        killphraseEnabled
    }

    public var killphraseEnabledText: String {
        if killphraseEnabled {
            "Enabled"
        } else {
            "None"
        }
    }

    public var encrypted: Bool {
        newEncryptionPassword.isNotBlank || existingEncryptionKey.isNotNil
    }

    public var encryptionEnabledText: String {
        if encrypted {
            "Enabled"
        } else {
            "None"
        }
    }

    public var killphraseEnabledIcon: String {
        if killphraseEnabled {
            "bolt.badge.checkmark.fill"
        } else {
            "bolt"
        }
    }

    /// The first line of the note, which is shown as the title
    public var titleLine: String {
        let firstLine = contents
            .split(separator: "\n")
            .lazy
            .filter(\.isNotBlank)
            .first
        return String(firstLine ?? "")
    }

    /// The second line of the note, used to preview the content.
    public var contentPreviewLine: String {
        guard !encrypted, previewMode == .titleAndFirstLine else { return "" }
        let secondLine = contents
            .split(separator: "\n")
            .lazy
            .filter(\.isNotBlank)
            .dropFirst()
            .first
        return String(secondLine ?? "")
    }
}

// MARK: - Helpers

extension SecureNoteDetailEdits {
    /// Create an `SecureNoteDetailEdits` in a blank state with initial input values, for creation.
    /// All initial values are sensible defaults, and it's locked as `defaults` say.
    public static func new(defaults: NewItemDefaults) -> SecureNoteDetailEdits {
        .init(
            contents: "",
            textFormat: .markdown,
            color: nil,
            viewConfig: .alwaysVisible,
            searchPassphrase: "",
            hasExistingSearchPassphrase: false,
            killphraseEnabled: false,
            newKillphrase: "",
            tags: [],
            lockState: defaults.lockState,
            relativeOrder: .min,
            existingEncryptionKey: nil,
            previewMode: .titleAndFirstLine,
        )
    }
}
