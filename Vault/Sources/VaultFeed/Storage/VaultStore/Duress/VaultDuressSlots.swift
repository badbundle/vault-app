import Foundation

/// The slots a vault's duress vaults go in (VAULT-23), and how making a duress vault hands them on.
///
/// Every vault's payload lists `count` (L) distinct slots, never its own (`VaultMetadata.duressSlots`). Making a
/// duress vault from vault V always creates it, W, in `V.duressSlots[0]`, so making another replaces the one before.
/// W's list is V's without its first entry, then one more slot chosen at random from the slots that aren't V's, W's
/// or already on the list.
///
/// **The real vault R is never the target for L + 1 levels of nesting.** The first L duress vaults in a chain made
/// from R go in the slots R listed, which never include R's own, and the next goes in the slot R chose to hand on,
/// which isn't R's either. From the level after that, a slot chosen by a duress vault, which can't know where R is,
/// may be R's. No design can do better without leaving a mark in every duress vault: see "Making a duress database,
/// from any vault" in `docs/on-device-encryption.md`.
///
/// **Every list looks alike.** The first vault's list is a uniformly random ordering of L of the other slots, and so
/// is every duress vault's, as a whole, so a vault's list doesn't show whether it's the real vault or a duress one.
/// The slots are chosen with the system's random number generator, which is cryptographically secure.
enum VaultDuressSlots {
    /// L: how many duress slots each vault lists.
    static let count = 10

    /// Where a duress vault goes, and the duress slots it gets.
    struct Placement: Equatable {
        /// The slot the duress vault is created in.
        var slot: Int
        /// The new vault's own duress slots.
        var duressSlots: [Int]
    }

    /// The duress slots for the first vault in a new file: `count` random slots other than its own.
    static func forFirstVault(inSlot index: Int) -> [Int] {
        Array(otherSlots(than: index).shuffled().prefix(count))
    }

    static func forFirstVault(inSlot index: Int, using generator: inout some RandomNumberGenerator) -> [Int] {
        Array(otherSlots(than: index).shuffled(using: &generator).prefix(count))
    }

    /// Where a duress vault made from the vault in slot `index`, which lists `duressSlots`, goes.
    ///
    /// - Throws: `VaultDuressVaultError.unavailable` if `duressSlots` isn't a list a vault in that slot could have.
    static func placement(madeFromSlot index: Int, duressSlots: [Int]) throws -> Placement {
        try placement(madeFromSlot: index, duressSlots: duressSlots) { $0.randomElement() }
    }

    static func placement(
        madeFromSlot index: Int,
        duressSlots: [Int],
        using generator: inout some RandomNumberGenerator,
    ) throws -> Placement {
        try placement(madeFromSlot: index, duressSlots: duressSlots) { $0.randomElement(using: &generator) }
    }

    /// - Parameter choose: Picks one of the slots it's given at random.
    private static func placement(
        madeFromSlot index: Int,
        duressSlots: [Int],
        choose: ([Int]) -> Int?,
    ) throws -> Placement {
        guard isValid(duressSlots, forSlot: index) else { throw VaultDuressVaultError.unavailable }
        let slot = duressSlots[0]
        let handedOn = Array(duressSlots.dropFirst())
        let excluded = Set(handedOn + [index, slot])
        // There are always five to choose from: sixteen slots, less the nine handed on and the two vaults'.
        guard let added = choose(VaultSlotFile.slotIndices.filter { !excluded.contains($0) }) else {
            throw VaultDuressVaultError.unavailable
        }
        return Placement(slot: slot, duressSlots: handedOn + [added])
    }

    private static func otherSlots(than index: Int) -> [Int] {
        VaultSlotFile.slotIndices.filter { $0 != index }
    }

    /// Whether `duressSlots` is a list a vault in slot `index` could have: `count` distinct slots of the file, none of
    /// them its own.
    static func isValid(_ duressSlots: [Int], forSlot index: Int) -> Bool {
        duressSlots.count == count
            && Set(duressSlots).count == count
            && duressSlots.allSatisfy { VaultSlotFile.slotIndices.contains($0) && $0 != index }
    }
}
