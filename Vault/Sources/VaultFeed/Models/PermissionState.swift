import Foundation

public enum PermissionState: Equatable, Hashable, Sendable {
    case undetermined
    case allowed
    case denied
    /// There's nothing to authenticate with: the device has no passcode, Face ID or Touch ID set up. It stays this
    /// way until one is, rather than asking for authentication that can only fail.
    case unavailable
}
