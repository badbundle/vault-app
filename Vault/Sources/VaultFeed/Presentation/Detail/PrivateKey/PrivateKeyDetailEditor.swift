import Foundation
import FoundationExtensions
import VaultCore
import VaultKeygen

/// @mockable
@MainActor
public protocol PrivateKeyDetailEditor {
    func createPrivateKey(initialEdits: PrivateKeyDetailEdits) async throws
    /// - Returns: The key the item is now encrypted with, which is new if the edits set a new password.
    func updatePrivateKey(id: Identifier<VaultItem>, edits: PrivateKeyDetailEdits) async throws
        -> DerivedEncryptionKey
    func deletePrivateKey(id: Identifier<VaultItem>) async throws
}
