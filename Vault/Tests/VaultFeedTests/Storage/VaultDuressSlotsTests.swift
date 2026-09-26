import Foundation
import Testing
@testable import VaultFeed

/// Where duress vaults go: every list the app writes is valid, and a chain of duress vaults made from the real vault
/// never reaches it within L + 1 = 11 levels.
struct VaultDuressSlotsTests {
    @Test
    func forFirstVault_listsTenDistinctSlotsOtherThanItsOwn() {
        var generator = SeededRandomNumberGenerator(seed: 1)
        for slot in VaultSlotFile.slotIndices {
            for _ in 0 ..< 50 {
                let duressSlots = VaultDuressSlots.forFirstVault(inSlot: slot, using: &generator)

                #expect(duressSlots.count == 10)
                #expect(VaultDuressSlots.isValid(duressSlots, forSlot: slot))
            }
        }
    }

    @Test
    func placement_goesInTheFirstSlotAndHandsOnTheRestWithOneNewSlot() throws {
        let duressSlots = [7, 2, 9, 0, 13, 5, 11, 1, 14, 3]
        var generator = SeededRandomNumberGenerator(seed: 2)

        let placement = try VaultDuressSlots.placement(madeFromSlot: 4, duressSlots: duressSlots, using: &generator)

        #expect(placement.slot == 7)
        #expect(Array(placement.duressSlots.prefix(9)) == [2, 9, 0, 13, 5, 11, 1, 14, 3])
        // Neither vault's slot, nor one already on the list: 6, 8, 10, 12 or 15.
        #expect([6, 8, 10, 12, 15].contains(placement.duressSlots[9]))
        #expect(VaultDuressSlots.isValid(placement.duressSlots, forSlot: placement.slot))
    }

    /// Making another duress vault from the same vault replaces the one before, in the same slot.
    @Test
    func placement_fromTheSameVault_isAlwaysTheSameSlot() throws {
        let duressSlots = [7, 2, 9, 0, 13, 5, 11, 1, 14, 3]
        var generator = SeededRandomNumberGenerator(seed: 3)

        let slots = try (0 ..< 20).map { _ in
            try VaultDuressSlots.placement(madeFromSlot: 4, duressSlots: duressSlots, using: &generator).slot
        }

        #expect(Set(slots) == [7])
    }

    /// The slot added to the list is chosen at random from all five it could be.
    @Test
    func placement_choosesTheNewSlotFromEveryCandidate() throws {
        let duressSlots = [7, 2, 9, 0, 13, 5, 11, 1, 14, 3]
        var generator = SeededRandomNumberGenerator(seed: 4)

        let added = try (0 ..< 200).map { _ in
            try VaultDuressSlots.placement(madeFromSlot: 4, duressSlots: duressSlots, using: &generator).duressSlots[9]
        }

        #expect(Set(added) == [6, 8, 10, 12, 15])
    }

    @Test(arguments: [
        [],
        [7, 2, 9, 0, 13, 5, 11, 1, 14],
        [7, 2, 9, 0, 13, 5, 11, 1, 14, 3, 6],
        [7, 2, 9, 0, 13, 5, 11, 1, 14, 7],
        [7, 2, 9, 0, 13, 5, 11, 1, 14, 4],
        [7, 2, 9, 0, 13, 5, 11, 1, 14, 16],
        [7, 2, 9, 0, 13, 5, 11, 1, 14, -1],
    ])
    func placement_fromAnInvalidList_throwsUnavailable(duressSlots: [Int]) {
        #expect(throws: VaultDuressVaultError.unavailable) {
            try VaultDuressSlots.placement(madeFromSlot: 4, duressSlots: duressSlots)
        }
    }
}

// MARK: - Chains

extension VaultDuressSlotsTests {
    /// Each level makes a duress vault from the one before, starting from the real vault, with random choices at
    /// every step. None of the first eleven lands on the real vault's slot, and every vault's list stays valid.
    @Test
    func chainFromTheRealVault_neverTargetsItWithinElevenLevels() throws {
        var generator = SeededRandomNumberGenerator(seed: 5)
        for _ in 0 ..< 2000 {
            let realSlot = Int.random(in: VaultSlotFile.slotIndices, using: &generator)
            let targets = try chain(fromSlot: realSlot, levels: 11, using: &generator)

            #expect(!targets.contains(realSlot))
        }
    }

    /// The bound is exact: from the twelfth level a slot chosen by a duress vault, which can't know where the real
    /// vault is, can land on it. That's the design's accepted limit (see "Making a duress database, from any
    /// vault").
    @Test
    func chainFromTheRealVault_canReachItAtTheTwelfthLevel() throws {
        var generator = SeededRandomNumberGenerator(seed: 6)
        var reachedAtTwelve = 0
        for _ in 0 ..< 200 {
            let realSlot = Int.random(in: VaultSlotFile.slotIndices, using: &generator)
            let targets = try chain(fromSlot: realSlot, levels: 12, using: &generator)
            if targets[11] == realSlot {
                reachedAtTwelve += 1
            }
        }

        #expect(reachedAtTwelve > 0)
    }

    /// The slots of the vaults made at each level, making each from the one before, starting from a first vault in
    /// `slot`.
    private func chain(
        fromSlot slot: Int,
        levels: Int,
        using generator: inout some RandomNumberGenerator,
    ) throws -> [Int] {
        var vault = (slot: slot, duressSlots: VaultDuressSlots.forFirstVault(inSlot: slot, using: &generator))
        var targets = [Int]()
        for _ in 0 ..< levels {
            let placement = try VaultDuressSlots.placement(
                madeFromSlot: vault.slot,
                duressSlots: vault.duressSlots,
                using: &generator,
            )
            #expect(VaultDuressSlots.isValid(placement.duressSlots, forSlot: placement.slot))
            #expect(!placement.duressSlots.contains(vault.slot))
            targets.append(placement.slot)
            vault = (placement.slot, placement.duressSlots)
        }
        return targets
    }
}
