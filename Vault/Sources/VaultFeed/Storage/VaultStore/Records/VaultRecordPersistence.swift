import Foundation

/// Where a `RecordVaultStore` saves each new state of the vault before it publishes it.
///
/// A store without one keeps the vault in memory only. An unlocked encrypted vault saves to its slot of the vault
/// file (`SlotFilePersistence`).
protocol VaultRecordPersistence: Sendable {
    /// Saves `state` in place of the state saved before.
    ///
    /// - Returns: `.saved`, or `.conflict` if another writer saved since this one last saved or loaded. Then nothing
    ///   is saved, and it returns what's saved now, for the store to take as its state.
    /// - Throws: If it can't save. What's saved stays as it was.
    mutating func save(_ state: VaultRecordState) throws -> VaultRecordSaveOutcome
}

/// What happened to a state `VaultRecordPersistence` was asked to save.
enum VaultRecordSaveOutcome: Equatable, Sendable {
    /// It's saved.
    case saved
    /// Another writer saved first, so it wasn't. `saved` is what's saved now.
    case conflict(saved: VaultRecordState)
}
