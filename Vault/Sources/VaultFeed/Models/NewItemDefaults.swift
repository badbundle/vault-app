import Foundation

/// What a new item starts with, as chosen in Settings.
///
/// These only set the starting values of an item being created: its editor can still change them, and changing
/// them in Settings never touches an existing item (MANIFESTO C1). Hiding an item, search passphrases and
/// killphrases have no defaults, as they're set up item by item (C1, C9).
public struct NewItemDefaults: Equatable, Hashable, Sendable {
    /// Whether a new code or note starts locked. Recovery phrases are always locked, whatever this says.
    public var lockNewItems: Bool
    /// Whether a new code starts out offered in QuickType.
    public var showNewCodesInQuickType: Bool

    /// Both off unless the user turns them on: nothing starts locked, and no code is offered to AutoFill until the
    /// user chooses it (MANIFESTO C7).
    public init(lockNewItems: Bool = false, showNewCodesInQuickType: Bool = false) {
        self.lockNewItems = lockNewItems
        self.showNewCodesInQuickType = showNewCodesInQuickType
    }

    /// The lock state a new code or note starts with.
    public var lockState: VaultItemLockState {
        lockNewItems ? .lockedWithNativeSecurity : .notLocked
    }
}
