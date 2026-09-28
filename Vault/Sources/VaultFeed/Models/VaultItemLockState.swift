import Foundation
import FoundationExtensions

public enum VaultItemLockState: Equatable, Hashable, CaseIterable, IdentifiableSelf, Sendable {
    /// This item is not locked and can be viewed immediately
    case notLocked
    /// The item is locked and secured at the OS level.
    ///
    /// For example, on iOS this requires the device password or biometric authentication.
    case lockedWithNativeSecurity
}

extension VaultItemLockState {
    public var isLocked: Bool {
        get {
            switch self {
            case .notLocked: false
            case .lockedWithNativeSecurity: true
            }
        }
        set {
            self = newValue ? .lockedWithNativeSecurity : .notLocked
        }
    }
}

extension VaultItemLockState {
    public var systemIconName: String {
        switch self {
        case .notLocked: "lock.open"
        case .lockedWithNativeSecurity: "lock"
        }
    }

    public var localizedTitle: String {
        switch self {
        case .notLocked: localized(key: "vaultItemLockState.notLocked.title")
        case .lockedWithNativeSecurity: localized(key: "vaultItemLockState.lockedWithNativeSecurity.title")
        }
    }
}
