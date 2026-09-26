import Foundation

/// Chooses the wrap time a rekey records in a slot's key box (`VaultSlotFile.OpenedSlot.wrappedAt`).
///
/// When one password opens more than one slot, the most recently wrapped wins. A wrap time read from a clock the user
/// can set back would let whoever holds the device choose which slot wins, and so test whether a password opens
/// another vault without counting an attempt. Every rewrap (`VaultPasswordChangeService`) takes its time from here.
///
/// This is the seam for the device-local monotonic wrap stamp (VAULT-51): each wrap later than the last one this
/// device made, and than the slot's own. Until that's in, `VaultWallClockWrapStamper` stands in for it.
public protocol VaultWrapStamping: Sendable {
    /// The wrap time for a slot being rewrapped, which was last wrapped at `previous`. It's after `previous`.
    func nextWrapStamp(rewrapping previous: Date) throws -> Date
}

/// The wall clock, but never at or before the slot's own wrap time. It doesn't remember the stamps it gave, so it
/// can't stop a clock set back from stamping a rewrap before another slot's wrap. The monotonic stamp (VAULT-51)
/// replaces it.
public struct VaultWallClockWrapStamper: VaultWrapStamping {
    private let now: @Sendable () -> Date

    public init() {
        self.init(now: { Date() })
    }

    init(now: @escaping @Sendable () -> Date) {
        self.now = now
    }

    public func nextWrapStamp(rewrapping previous: Date) -> Date {
        max(now(), previous.addingTimeInterval(0.001))
    }
}
