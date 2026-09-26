import CryptoKit
import Foundation

/// The key that wraps a slot's data key: `K_pw`, derived from the app lock password, or `D`, the device key used
/// while the password is off.
///
/// A slot's wrap key is `HKDF-SHA256(ikm: root key, salt: slot nonce, info)`, with a different `info` for each kind,
/// so a password key and a device key with the same bytes don't open each other's slots.
public struct VaultSlotRootKey: Sendable {
    enum Kind: Sendable {
        case password
        case device

        var info: Data {
            switch self {
            case .password: Data("vault.slot.wrap.password.v1".utf8)
            case .device: Data("vault.slot.wrap.device.v1".utf8)
            }
        }
    }

    let kind: Kind
    let key: SymmetricKey

    /// `K_pw`, derived from the app lock password with the file's Argon2id parameters and salt.
    ///
    /// `VaultSlotFile.Header.passwordKey(for:)` derives it.
    public static func password(derivedKey: SymmetricKey) -> VaultSlotRootKey {
        VaultSlotRootKey(kind: .password, key: derivedKey)
    }

    /// `D`, the 256-bit device key from the keychain, which wraps the open vault while the password is off.
    public static func device(_ key: SymmetricKey) -> VaultSlotRootKey {
        VaultSlotRootKey(kind: .device, key: key)
    }

    /// `W_i`, the wrap key for the slot with this nonce.
    func wrapKey(slotNonce: Data) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: key, salt: slotNonce, info: kind.info, outputByteCount: 32)
    }
}
