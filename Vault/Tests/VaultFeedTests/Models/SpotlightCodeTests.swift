import Foundation
import FoundationExtensions
import TestHelpers
import Testing
import VaultCore
@testable import VaultFeed

struct SpotlightCodeTests {
    @Test
    func codes_showsTheSiteNameOfAVisibleUnlockedCode() {
        let item = code(issuer: "GitHub", accountName: "bradley@example.com")

        let codes = SpotlightCode.codes(in: [item], isTurnedOn: true, isAppLockOn: false)

        #expect(codes == [SpotlightCode(id: item.id, name: "GitHub")])
    }

    @Test
    func codes_isEmptyUntilTurnedOn() {
        let codes = SpotlightCode.codes(in: [code(issuer: "GitHub")], isTurnedOn: false, isAppLockOn: false)

        #expect(codes.isEmpty)
    }

    /// Spotlight can be searched without unlocking Vault, which App Lock guards.
    @Test
    func codes_isEmptyWhileAppLockIsOn() {
        let codes = SpotlightCode.codes(in: [code(issuer: "GitHub")], isTurnedOn: true, isAppLockOn: true)

        #expect(codes.isEmpty)
    }

    @Test
    func codes_neverShowsNotesRecoveryPhrasesOrEncryptedItems() {
        let items = [
            uniqueVaultItem(item: .secureNote(anySecureNote(title: "Home Wi-Fi"))),
            uniqueVaultItem(item: .recoveryPhrase(anyRecoveryPhrase(title: "Wallet"))),
            uniqueVaultItem(item: .encryptedItem(anyEncryptedItem(title: "GitHub"))),
        ]

        let codes = SpotlightCode.codes(in: items, isTurnedOn: true, isAppLockOn: false)

        #expect(codes.isEmpty)
    }

    @Test
    func codes_neverShowsALockedCode() {
        let codes = SpotlightCode.codes(
            in: [code(issuer: "Monzo", lockState: .lockedWithNativeSecurity)],
            isTurnedOn: true,
            isAppLockOn: false,
        )

        #expect(codes.isEmpty)
    }

    /// Hidden until searched for, so the feed doesn't show it either.
    @Test
    func codes_neverShowsAHiddenCode() {
        let codes = SpotlightCode.codes(
            in: [code(issuer: "Secret", visibility: .onlySearch, searchableLevel: .onlyPassphrase)],
            isTurnedOn: true,
            isAppLockOn: false,
        )

        #expect(codes.isEmpty)
    }

    @Test(arguments: [VaultItemSearchableLevel.none, .onlyPassphrase])
    func codes_neverShowsACodeVaultsSearchCantFindByName(searchableLevel: VaultItemSearchableLevel) {
        let codes = SpotlightCode.codes(
            in: [code(issuer: "GitHub", searchableLevel: searchableLevel)],
            isTurnedOn: true,
            isAppLockOn: false,
        )

        #expect(codes.isEmpty)
    }

    @Test
    func codes_showsACodeFoundOnlyByItsTitle() {
        let item = code(issuer: "GitHub", searchableLevel: .onlyTitle)

        let codes = SpotlightCode.codes(in: [item], isTurnedOn: true, isAppLockOn: false)

        #expect(codes.map(\.name) == ["GitHub"])
    }

    /// Without a site name, only the account name is left, and that's never shown.
    @Test
    func codes_leavesOutACodeWithoutASiteName() {
        let codes = SpotlightCode.codes(
            in: [code(issuer: "  ", accountName: "bradley@example.com")],
            isTurnedOn: true,
            isAppLockOn: false,
        )

        #expect(codes.isEmpty)
    }

    /// Leaving it out would let someone compare Spotlight with the feed to find the codes with one (MANIFESTO C5).
    @Test
    func codes_showsACodeWithAKillphraseLikeAnyOther() {
        let item = code(issuer: "Coinbase", killphrase: "burn it")

        let codes = SpotlightCode.codes(in: [item], isTurnedOn: true, isAppLockOn: false)

        #expect(codes == [SpotlightCode(id: item.id, name: "Coinbase")])
    }
}

// MARK: - Helpers

extension SpotlightCodeTests {
    private func code(
        issuer: String,
        accountName: String = "",
        visibility: VaultItemVisibility = .always,
        searchableLevel: VaultItemSearchableLevel = .full,
        killphrase: String? = nil,
        lockState: VaultItemLockState = .notLocked,
    ) -> VaultItem {
        uniqueVaultItem(
            item: .otpCode(anyOTPAuthCode(accountName: accountName, issuerName: issuer)),
            visibility: visibility,
            searchableLevel: searchableLevel,
            killphrase: killphrase,
            lockState: lockState,
        )
    }
}
