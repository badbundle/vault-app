import Foundation

/// Whether a process has the memory for a save that replaces the encrypted vault file: what the AutoFill extension
/// checks before it writes, such as advancing a HOTP counter, since the system stops an extension that runs out.
///
/// At its peak a save holds the file twice, the new file and the copy read back to verify it, and the vault's JSON
/// four times over: encoded, decompressed again to verify it, and the records in memory and their verified copy,
/// which take about as much as their JSON. On top of that, the same margin as unlocking. See "Memory and the AutoFill
/// extension" in `docs/on-device-encryption.md`. The app doesn't check: it can always write.
struct VaultWriteMemoryCheck: Sendable {
    /// The memory the process can still use, or `nil` if it has no limit.
    let availableMemory: @Sendable () -> Int?
    /// Called when a save doesn't go ahead for want of memory, so the extension can send the user to Vault.
    let onNotEnoughMemory: @Sendable () -> Void

    /// Whether a save of `jsonSize` bytes of JSON into a file of `fileSize` bytes can go ahead.
    func allowsSave(fileSize: Int, jsonSize: Int) -> Bool {
        guard let available = availableMemory() else { return true }
        let needed = 2 * fileSize + 4 * jsonSize + VaultUnlockService.memoryMargin
        guard available >= needed else {
            onNotEnoughMemory()
            return false
        }
        return true
    }
}
