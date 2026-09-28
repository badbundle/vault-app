import Foundation
import FoundationExtensions
import Testing
import VaultCore
@testable import VaultFeed

struct VaultItemWidgetEligibilityTests {
    @Test
    func eligible_whenAllConditionsHold() {
        let item = uniqueVaultItem(
            visibility: .always,
            searchableLevel: .full,
            killphrase: nil,
            lockState: .notLocked,
        )
        #expect(VaultItemWidgetEligibility.isEligible(item))
    }

    @Test
    func ineligible_whenPayloadIsNotOTP() {
        let note = SecureNote(title: "t", contents: "c", format: .markdown)
        let item = uniqueVaultItem(item: .secureNote(note))
        #expect(!VaultItemWidgetEligibility.isEligible(item))
    }

    @Test
    func ineligible_whenLocked() {
        let item = uniqueVaultItem(lockState: .lockedWithNativeSecurity)
        #expect(!VaultItemWidgetEligibility.isEligible(item))
    }

    @Test
    func ineligible_whenVisibilityIsOnlySearch() {
        let item = uniqueVaultItem(visibility: .onlySearch)
        #expect(!VaultItemWidgetEligibility.isEligible(item))
    }

    @Test
    func ineligible_whenSearchableLevelIsOnlyPassphrase() {
        let item = uniqueVaultItem(searchableLevel: .onlyPassphrase)
        #expect(!VaultItemWidgetEligibility.isEligible(item))
    }

    /// As in Spotlight, a code with a killphrase shows like any other visible code (MANIFESTO C5).
    @Test
    func eligible_whenKillphraseIsSet() {
        let item = uniqueVaultItem(killphrase: "any-phrase")
        #expect(VaultItemWidgetEligibility.isEligible(item))
    }

    @Test
    func metadataOnlyOverload_matchesMetadataFields() {
        let metadata = anyVaultItemMetadata(
            visibility: .always,
            searchableLevel: .full,
            killphrase: nil,
            lockState: .notLocked,
        )
        #expect(VaultItemWidgetEligibility.isEligible(metadata: metadata))

        let lockedMetadata = anyVaultItemMetadata(lockState: .lockedWithNativeSecurity)
        #expect(!VaultItemWidgetEligibility.isEligible(metadata: lockedMetadata))
    }
}
