/// Which way the lock is going.
public enum VaultLockTransition: Hashable, Sendable {
    case lock
    case unlock
}
