import Foundation
import VaultFeed

/// How the vault is stored, as an AutoFill request finds it. Decided afresh for every request, since the extension's
/// process can outlive one and the app can turn encryption on meanwhile.
enum AutofillVaultStorage {
    /// In the plain store: device authentication unlocks it, if the app lock is on.
    case plain
    /// Encrypted: the App Lock Password unlocks it, after device authentication.
    case encrypted(any AutofillPasswordUnlocking)
    /// Being converted, or its state can't be read: the extension can't open it, and the user has to open Vault.
    case unavailable
}

/// The App Lock Password as the AutoFill extension unlocks with it.
@MainActor
protocol AutofillPasswordUnlocking: AppLockPasswordService, AnyObject {
    /// Called when an unlock or a save doesn't go ahead for want of memory.
    var onNotEnoughMemory: (@MainActor () -> Void)? { get set }
    /// Whether the extension has the memory to derive the key.
    func hasMemoryHeadroomToUnlock() async throws -> Bool
    /// Locks the vault, if it's open, and forgets everything read from it.
    func lockVault() async
}

extension AutofillVaultPasswordService: AutofillPasswordUnlocking {}
