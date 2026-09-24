import Foundation
import FoundationExtensions
import VaultCore
import VaultKeygen

/// @mockable
@MainActor
public protocol RecoveryPhraseDetailEditor {
    func createRecoveryPhrase(initialEdits: RecoveryPhraseDetailEdits) async throws
    /// - Returns: The key the item is now encrypted with, which is new if the edits set a new password.
    func updateRecoveryPhrase(id: Identifier<VaultItem>, edits: RecoveryPhraseDetailEdits) async throws
        -> DerivedEncryptionKey
    func deleteRecoveryPhrase(id: Identifier<VaultItem>) async throws
}
