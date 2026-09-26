/// What the vault door is doing.
public enum VaultLockTransition: Hashable, Sendable {
    case lock
    case unlock
    /// A password decrypting an item. The wheel works a combination, turning one
    /// way, back the other and then round to seat, and the door swings wide: a
    /// different mechanism from the unlock's single spin, because decrypting with
    /// a password is not unlocking with the device.
    case decrypt
    /// A password that didn't decrypt the item: the wheel catches against the
    /// bolts and the door rattles in its frame, still shut.
    case decryptionFailed
}
