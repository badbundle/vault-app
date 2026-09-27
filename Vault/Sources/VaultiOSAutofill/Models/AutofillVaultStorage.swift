import Foundation
import VaultFeed

/// How the vault is stored, as an AutoFill request finds it. Decided afresh for every request, since the extension's
/// process can outlive one, and the app can turn encryption, or the App Lock Password, on or off meanwhile.
enum AutofillVaultStorage: Equatable {
    /// In the plain store: device authentication opens it, if the app lock is on.
    case plain
    /// Encrypted, with the App Lock Password off: the device key opens it, and device authentication is all it
    /// takes, as for a plain vault.
    case deviceKey
    /// Encrypted: the App Lock Password opens it, after device authentication.
    case password
    /// Being converted, rekeyed or erased, or its state can't be read: the extension can't open it, and the user has
    /// to open Vault.
    case unavailable

    init(_ mode: VaultAccessMode) {
        self = switch mode {
        case .plain: .plain
        case .deviceKey: .deviceKey
        case .password: .password
        case .unavailable: .unavailable
        }
    }
}

/// How the AutoFill extension opens the encrypted vault: with the App Lock Password, or the device key.
@MainActor
protocol AutofillVaultUnlocking: AppLockPasswordService, AnyObject {
    /// Called when an unlock, an open or a save doesn't go ahead for want of memory.
    var onNotEnoughMemory: (@MainActor () -> Void)? { get set }
    /// Whether the extension has the memory to open the vault.
    func hasMemoryHeadroomToUnlock() async throws -> Bool
    /// Opens the vault with the device key, once there's the memory. Throws `AutofillVaultService.NotEnoughMemoryError`
    /// if there isn't.
    func openWithDeviceKey() async throws
    /// Locks the vault, if it's open, and forgets everything read from it.
    func lockVault() async
}

extension AutofillVaultService: AutofillVaultUnlocking {}
