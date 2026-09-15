import Foundation
import FoundationExtensions
import SwiftData
import TestHelpers
import Testing
import VaultCore
@testable import VaultFeed

final class PersistedLocalVaultStoreTests {
    private var sut: PersistedLocalVaultStore

    init() async throws {
        let container = try ModelContainer(
            for: PersistedVaultItem.self,
            configurations: .init(isStoredInMemoryOnly: true),
        )
        sut = PersistedLocalVaultStore(modelContainer: container)
        await sut.updateSortOrder(.createdDate)
    }

    @Test
    func retrieveAll_deliversEmptyOnEmptyStore() async throws {
        let result = try await sut.retrieve(query: .init())
        #expect(result == .empty())
    }

    @Test
    func retrieveAll_hasNoSideEffectsOnEmptyStore() async throws {
        let result1 = try await sut.retrieve(query: .init())
        #expect(result1 == .empty())
        let result2 = try await sut.retrieve(query: .init())
        #expect(result2 == .empty())
    }

    @Test
    func retrieveAll_deliversSingleCodeOnNonEmptyStore() async throws {
        let code = uniqueVaultItem().makeWritable()
        try await sut.insert(item: code)

        let result = try await sut.retrieve(query: .init())
        #expect(result.items.map(\.item.otpCode) == [code.item.otpCode])
        #expect(result.errors == [])
    }

    @Test
    func retrieveAll_deliversMultipleCodesOnNonEmptyStore() async throws {
        let codes: [VaultItem.Write] = [
            uniqueVaultItem().makeWritable(),
            uniqueVaultItem().makeWritable(),
            uniqueVaultItem().makeWritable(),
        ]
        for code in codes {
            try await sut.insert(item: code)
        }

        let result = try await sut.retrieve(query: .init())
        #expect(result.items.map(\.item.otpCode) == codes.map(\.item.otpCode))
        #expect(result.errors == [])
    }

    @Test
    func retrieveAll_hasNoSideEffectsOnNonEmptyStore() async throws {
        let codes: [VaultItem.Write] = [
            uniqueVaultItem().makeWritable(),
            uniqueVaultItem().makeWritable(),
            uniqueVaultItem().makeWritable(),
        ]
        for code in codes {
            try await sut.insert(item: code)
        }

        let result1 = try await sut.retrieve(query: .init())
        #expect(result1.items.map(\.item.otpCode) == codes.map(\.item.otpCode))
        #expect(result1.errors == [])
        let result2 = try await sut.retrieve(query: .init())
        #expect(result2.items.map(\.item.otpCode) == codes.map(\.item.otpCode))
        #expect(result2.errors == [])
    }

    @Test
    func retrieveAll_doesNotReturnSearchOnlyItems() async throws {
        let codes: [VaultItem.Write] = [
            uniqueVaultItem(visibility: .onlySearch).makeWritable(),
            uniqueVaultItem(visibility: .onlySearch).makeWritable(),
            uniqueVaultItem(visibility: .onlySearch).makeWritable(),
        ]
        for code in codes {
            try await sut.insert(item: code)
        }

        let result = try await sut.retrieve(query: .init())
        #expect(result.items.isEmpty == true)
        #expect(result.errors.isEmpty == true)
    }

    @Test
    func retrieveAll_returnsAlwaysVisibleItems() async throws {
        let codes: [VaultItem.Write] = [
            uniqueVaultItem(visibility: .always).makeWritable(),
            uniqueVaultItem(visibility: .onlySearch).makeWritable(),
            uniqueVaultItem(visibility: .always).makeWritable(),
        ]
        for code in codes {
            try await sut.insert(item: code)
        }

        let result = try await sut.retrieve(query: .init())
        #expect(result.items.count == 2)
        #expect(result.errors == [])
    }

    @Test
    func retrieveAll_relativeOrderReturnsItemsInRelativeOrder() async throws {
        await sut.updateSortOrder(.relativeOrder)

        let codes: [VaultItem.Write] = [
            uniqueVaultItem(relativeOrder: 3).makeWritable(),
            uniqueVaultItem(relativeOrder: 3).makeWritable(),
            uniqueVaultItem(relativeOrder: 1).makeWritable(),
            uniqueVaultItem(relativeOrder: 2).makeWritable(),
            uniqueVaultItem(relativeOrder: .min).makeWritable(),
            uniqueVaultItem(relativeOrder: 99).makeWritable(),
        ]
        var ids = [Identifier<VaultItem>]()
        for code in codes {
            let id = try await sut.insert(item: code)
            ids.append(id)
        }

        let result = try await sut.retrieve(query: .init())
        #expect(result.items.map(\.id) == [
            ids[4], // min (default position)
            ids[2], // 1
            ids[3], // 2
            ids[1], // 3, added second (more recently)
            ids[0], // 3, added first (less recently)
            ids[5], // 99
        ])
        #expect(result.errors == [])
    }

    @Test
    func retrieveAll_returnsCorruptedItemsAsErrors() async throws {
        let codes: [VaultItem.Write] = [
            uniqueVaultItem().makeWritable(),
            uniqueVaultItem().makeWritable(),
            uniqueVaultItem().makeWritable(),
        ]
        var ids = [Identifier<VaultItem>]()
        for code in codes {
            let id = try await sut.insert(item: code)
            ids.append(id)
        }

        // Introduce a corruption error on the first item
        try await sut.corruptItemAlgorithm(id: ids[0])

        let result = try await sut.retrieve(query: .init())
        #expect(result.items.map(\.id) == Array(ids[1...]))
        #expect(result.errors == [.failedToDecode(.invalidAlgorithm)])
    }

    @Test
    func retrieveAll_returnsAllItemsCorrupted() async throws {
        let codes: [VaultItem.Write] = [
            uniqueVaultItem().makeWritable(),
            uniqueVaultItem().makeWritable(),
            uniqueVaultItem().makeWritable(),
        ]
        for code in codes {
            let id = try await sut.insert(item: code)
            // Corrupt all items
            try await sut.corruptItemAlgorithm(id: id)
        }

        let result = try await sut.retrieve(query: .init())
        #expect(result.items == [])
        #expect(result.errors == [
            .failedToDecode(.invalidAlgorithm),
            .failedToDecode(.invalidAlgorithm),
            .failedToDecode(.invalidAlgorithm),
        ])
    }

    @Test
    func retrieveMatchingQuery_returnsEmptyOnEmptyStoreAndEmptyQuery() async throws {
        let query = VaultStoreQuery(filterText: "")
        let result = try await sut.retrieve(query: query)
        #expect(result.items == [])
        #expect(result.errors == [])
    }

    @Test
    func retrieveMatchingQuery_returnsEmptyOnEmptyStore() async throws {
        let query = VaultStoreQuery(filterText: "any")
        let result = try await sut.retrieve(query: query)
        #expect(result.items == [])
        #expect(result.errors == [])
    }

    @Test
    func retrieveMatchingQuery_hasNoSideEffectsOnEmptyStore() async throws {
        let query = VaultStoreQuery(filterText: "any")
        let result1 = try await sut.retrieve(query: query)
        #expect(result1.items == [])
        #expect(result1.errors == [])
        let result2 = try await sut.retrieve(query: query)
        #expect(result2.items == [])
        #expect(result2.errors == [])
    }

    @Test
    func retrieveMatchingQuery_returnsEmptyForNoQueryMatches() async throws {
        let codes: [VaultItem.Write] = [
            anySecureNote().wrapInAnyVaultItem().makeWritable(),
            anyOTPAuthCode().wrapInAnyVaultItem().makeWritable(),
        ]
        for code in codes {
            try await sut.insert(item: code)
        }

        let query = VaultStoreQuery(filterText: "any")
        let result = try await sut.retrieve(query: query)
        #expect(result.items == [])
        #expect(result.errors == [])
    }

    @Test
    func retrieveMatchingQuery_deliversSingleMatchOnMatchingQuery() async throws {
        let codes: [VaultItem.Write] = [
            anySecureNote().wrapInAnyVaultItem(userDescription: "yes").makeWritable(),
            anyOTPAuthCode().wrapInAnyVaultItem().makeWritable(),
        ]
        for code in codes {
            try await sut.insert(item: code)
        }

        let query = VaultStoreQuery(filterText: "yes")
        let result = try await sut.retrieve(query: query)
        #expect(result.items.count == 1)
        #expect(result.items.compactMap(\.item.secureNote) == codes.compactMap(\.item.secureNote))
        #expect(result.errors == [])
    }

    @Test
    func retrieveMatchingQuery_hasNoSideEffectsOnSingleMatch() async throws {
        let codes: [VaultItem.Write] = [
            anySecureNote().wrapInAnyVaultItem(userDescription: "yes").makeWritable(),
            anyOTPAuthCode().wrapInAnyVaultItem(userDescription: "no").makeWritable(),
        ]
        for code in codes {
            try await sut.insert(item: code)
        }

        let query1 = VaultStoreQuery(filterText: "yes")
        let result1 = try await sut.retrieve(query: query1)
        #expect(result1.items.count == 1)
        #expect(result1.items.compactMap(\.item.secureNote) == codes.compactMap(\.item.secureNote))
        #expect(result1.errors == [])
        let query2 = VaultStoreQuery(filterText: "yes")
        let result2 = try await sut.retrieve(query: query2)
        #expect(result2.items.count == 1)
        #expect(result2.items.compactMap(\.item.secureNote) == codes.compactMap(\.item.secureNote))
        #expect(result2.errors == [])
    }

    @Test
    func retrieveMatchingQuery_deliversMultipleMatchesOnMatchingQuery() async throws {
        let codes: [VaultItem.Write] = [
            anySecureNote().wrapInAnyVaultItem().makeWritable(),
            anyOTPAuthCode().wrapInAnyVaultItem().makeWritable(),
            uniqueVaultItem(userDescription: "no").makeWritable(),
            uniqueVaultItem(userDescription: "yes").makeWritable(),
            uniqueVaultItem(userDescription: "no").makeWritable(),
            uniqueVaultItem(userDescription: "yess").makeWritable(),
            uniqueVaultItem(userDescription: "yesss").makeWritable(),
            uniqueVaultItem(userDescription: "no").makeWritable(),
        ]
        for code in codes {
            try await sut.insert(item: code)
        }

        let query = VaultStoreQuery(filterText: "yes")
        let result = try await sut.retrieve(query: query)
        #expect(result.items.count == 3)
        #expect(result.items.map(\.metadata.userDescription) == ["yes", "yess", "yesss"])
        #expect(result.errors == [])
    }

    @Test
    func retrieveMatchingQuery_matchesUserDescription() async throws {
        let codes: [VaultItem.Write] = [
            anyOTPAuthCode().wrapInAnyVaultItem().makeWritable(),
            uniqueVaultItem().makeWritable(),
            uniqueVaultItem(userDescription: "x").makeWritable(),
            uniqueVaultItem(userDescription: "a").makeWritable(),
            uniqueVaultItem(userDescription: "c").makeWritable(),
            uniqueVaultItem(userDescription: "b").makeWritable(),
            uniqueVaultItem(userDescription: "----a----").makeWritable(),
            uniqueVaultItem(userDescription: "----A----").makeWritable(),
            uniqueVaultItem(userDescription: "x").makeWritable(),
        ]
        for code in codes {
            try await sut.insert(item: code)
        }

        let query = VaultStoreQuery(filterText: "a")
        let result = try await sut.retrieve(query: query)
        #expect(result.items.count == 3)
        #expect(result.items.map(\.metadata.userDescription) == ["a", "----a----", "----A----"])
        #expect(result.errors == [])
    }

    @Test
    func retrieveMatchingQuery_matchesOTPAccountName() async throws {
        let codes: [VaultItem.Write] = [
            anySecureNote().wrapInAnyVaultItem().makeWritable(),
            anyOTPAuthCode(accountName: "a").wrapInAnyVaultItem().makeWritable(),
            anyOTPAuthCode(accountName: "x").wrapInAnyVaultItem().makeWritable(),
            anyOTPAuthCode(accountName: "----A----").wrapInAnyVaultItem().makeWritable(),
        ]
        for code in codes {
            try await sut.insert(item: code)
        }

        let query = VaultStoreQuery(filterText: "a")
        let result = try await sut.retrieve(query: query)
        #expect(result.items.count == 2)
        #expect(result.items.compactMap(\.item.otpCode?.data.accountName) == ["a", "----A----"])
        #expect(result.errors == [])
    }

    @Test
    func retrieveMatchingQuery_matchesOTPIssuer() async throws {
        let codes: [VaultItem.Write] = [
            anySecureNote().wrapInAnyVaultItem().makeWritable(),
            anyOTPAuthCode(issuerName: "a").wrapInAnyVaultItem().makeWritable(),
            anyOTPAuthCode(issuerName: "x").wrapInAnyVaultItem().makeWritable(),
            anyOTPAuthCode(issuerName: "----A----").wrapInAnyVaultItem().makeWritable(),
        ]
        for code in codes {
            try await sut.insert(item: code)
        }

        let query = VaultStoreQuery(filterText: "a")
        let result = try await sut.retrieve(query: query)
        #expect(result.items.count == 2)
        #expect(result.items.compactMap(\.item.otpCode?.data.issuer) == ["a", "----A----"])
        #expect(result.errors == [])
    }

    @Test
    func retrieveMatchingQuery_matchesNoteDetailsTitle() async throws {
        let codes: [VaultItem.Write] = [
            anySecureNote().wrapInAnyVaultItem().makeWritable(),
            anySecureNote(title: "a").wrapInAnyVaultItem().makeWritable(),
            anySecureNote(title: "x").wrapInAnyVaultItem().makeWritable(),
            anySecureNote(title: "----A----").wrapInAnyVaultItem().makeWritable(),
        ]
        for code in codes {
            try await sut.insert(item: code)
        }

        let query = VaultStoreQuery(filterText: "a")
        let result = try await sut.retrieve(query: query)
        #expect(result.items.count == 2)
        #expect(result.items.compactMap(\.item.secureNote?.title) == ["a", "----A----"])
        #expect(result.errors == [])
    }

    @Test
    func retrieveMatchingQuery_skipsNonSearchableNoteTitle() async throws {
        let codes: [VaultItem.Write] = [
            anySecureNote().wrapInAnyVaultItem().makeWritable(),
            anySecureNote(title: "a").wrapInAnyVaultItem(searchableLevel: .none).makeWritable(), // skipped
            anySecureNote(title: "x").wrapInAnyVaultItem().makeWritable(),
            anySecureNote(title: "----A----").wrapInAnyVaultItem().makeWritable(),
        ]
        for code in codes {
            try await sut.insert(item: code)
        }

        let query = VaultStoreQuery(filterText: "a")
        let result = try await sut.retrieve(query: query)
        #expect(result.items.count == 1)
        #expect(result.items.compactMap(\.item.secureNote?.title) == ["----A----"])
        #expect(result.errors == [])
    }

    @Test
    func retrieveMatchingQuery_matchesNoteDetailsContents() async throws {
        let codes: [VaultItem.Write] = [
            anySecureNote().wrapInAnyVaultItem().makeWritable(),
            anySecureNote(contents: "a").wrapInAnyVaultItem().makeWritable(),
            anySecureNote(contents: "x").wrapInAnyVaultItem().makeWritable(),
            anySecureNote(contents: "----A----").wrapInAnyVaultItem().makeWritable(),
        ]
        for code in codes {
            try await sut.insert(item: code)
        }

        let query = VaultStoreQuery(filterText: "a")
        let result = try await sut.retrieve(query: query)
        #expect(result.items.count == 2)
        #expect(result.items.compactMap(\.item.secureNote?.contents) == ["a", "----A----"])
        #expect(result.errors == [])
    }

    @Test
    func retrieveMatchingQuery_skipsNonSearchableNoteContents() async throws {
        let codes: [VaultItem.Write] = [
            anySecureNote().wrapInAnyVaultItem().makeWritable(),
            anySecureNote(contents: "a").wrapInAnyVaultItem(searchableLevel: .none).makeWritable(), // skipped
            anySecureNote(contents: "x").wrapInAnyVaultItem().makeWritable(),
            anySecureNote(contents: "----A----").wrapInAnyVaultItem().makeWritable(),
        ]
        for code in codes {
            try await sut.insert(item: code)
        }

        let query = VaultStoreQuery(filterText: "a")
        let result = try await sut.retrieve(query: query)
        #expect(result.items.count == 1)
        #expect(result.items.compactMap(\.item.secureNote?.contents) == ["----A----"])
        #expect(result.errors == [])
    }

    @Test
    func retrieveMatchingQuery_matchesEncryptedItemTitle() async throws {
        let codes: [VaultItem.Write] = [
            anyEncryptedItem(title: "a").wrapInAnyVaultItem().makeWritable(),
            anyEncryptedItem(title: "b").wrapInAnyVaultItem().makeWritable(),
            anyEncryptedItem(title: "----A----").wrapInAnyVaultItem().makeWritable(),
            anyEncryptedItem(title: "x").wrapInAnyVaultItem().makeWritable(),
        ]
        for code in codes {
            try await sut.insert(item: code)
        }

        let query = VaultStoreQuery(filterText: "a")
        let result = try await sut.retrieve(query: query)
        #expect(result.items.count == 2)
        #expect(result.items.compactMap(\.item.encryptedItem?.title) == ["a", "----A----"])
        #expect(result.errors == [])
    }

    @Test
    func retrieveMatchingQuery_skipsNonSearchableEncryptedItemTitles() async throws {
        let codes: [VaultItem.Write] = [
            anyEncryptedItem(title: "a").wrapInAnyVaultItem(searchableLevel: .none).makeWritable(), // skipped
            anyEncryptedItem(title: "b").wrapInAnyVaultItem().makeWritable(),
            anyEncryptedItem(title: "----A----").wrapInAnyVaultItem().makeWritable(),
            anyEncryptedItem(title: "x").wrapInAnyVaultItem().makeWritable(),
        ]
        for code in codes {
            try await sut.insert(item: code)
        }

        let query = VaultStoreQuery(filterText: "a")
        let result = try await sut.retrieve(query: query)
        #expect(result.items.count == 1)
        #expect(result.items.compactMap(\.item.encryptedItem?.title) == ["----A----"])
        #expect(result.errors == [])
    }

    @Test
    func retrieveMatchingQuery_filtersByTagsAsWell() async throws {
        let tag1 = try await sut.insertTag(item: anyVaultItemTag().makeWritable())

        let codes: [VaultItem.Write] = [
            anySecureNote().wrapInAnyVaultItem(tags: [tag1]).makeWritable(),
            anySecureNote(contents: "a").wrapInAnyVaultItem(tags: [tag1]).makeWritable(),
            anySecureNote(contents: "x").wrapInAnyVaultItem(tags: [tag1]).makeWritable(),
            anySecureNote(contents: "----A----").wrapInAnyVaultItem(tags: []).makeWritable(),
            // not tagged, so not returned
        ]
        for code in codes {
            try await sut.insert(item: code)
        }

        let query = VaultStoreQuery(filterText: "a", filterTags: [tag1])
        let result = try await sut.retrieve(query: query)
        #expect(result.items.count == 1)
        #expect(result.items.compactMap(\.item.secureNote?.contents) == ["a"])
        #expect(result.errors == [])
    }

    @Test
    func retrieveMatchingQuery_combinesResultsFromDifferentFields() async throws {
        let codes: [VaultItem.Write] = [
            anySecureNote().wrapInAnyVaultItem(userDescription: "a").makeWritable(),
            anySecureNote(title: "aa").wrapInAnyVaultItem().makeWritable(),
            anySecureNote(contents: "aaa").wrapInAnyVaultItem().makeWritable(),
            anyOTPAuthCode().wrapInAnyVaultItem(userDescription: "aaaa").makeWritable(),
            anyOTPAuthCode(accountName: "aaaaa").wrapInAnyVaultItem().makeWritable(),
            anyOTPAuthCode(issuerName: "aaaaaa").wrapInAnyVaultItem().makeWritable(),
        ]
        for code in codes {
            try await sut.insert(item: code)
        }

        let query = VaultStoreQuery(filterText: "a")
        let result = try await sut.retrieve(query: query)
        #expect(result.items.count == 6, "All items should be matched on the specified fields")
        #expect(result.errors == [])
    }

    @Test
    func retrieveMatchingQuery_returnsMatchesForAllQueryStates() async throws {
        let codes: [VaultItem.Write] = [
            anySecureNote().wrapInAnyVaultItem(userDescription: "a", visibility: .onlySearch).makeWritable(),
            anySecureNote(title: "aa").wrapInAnyVaultItem(visibility: .always).makeWritable(),
            anySecureNote(contents: "aaa").wrapInAnyVaultItem(visibility: .onlySearch).makeWritable(),
            anyOTPAuthCode().wrapInAnyVaultItem(userDescription: "aaaa", visibility: .onlySearch).makeWritable(),
            anyOTPAuthCode(accountName: "aaaaa").wrapInAnyVaultItem(visibility: .onlySearch).makeWritable(),
            anyOTPAuthCode(issuerName: "aaaaaa").wrapInAnyVaultItem(visibility: .onlySearch).makeWritable(),
        ]
        for code in codes {
            try await sut.insert(item: code)
        }

        let query = VaultStoreQuery(filterText: "a")
        let result = try await sut.retrieve(query: query)
        #expect(result.items.count == 6, "All items should be matched on the specified fields")
        #expect(result.errors == [])
    }

    @Test
    func retrieveMatchingQuery_doesNotReturnNotesSearchingByContent() async throws {
        let codes: [VaultItem.Write] = [
            anySecureNote(contents: "aaa").wrapInAnyVaultItem(searchableLevel: .onlyTitle).makeWritable(),
            anySecureNote(contents: "aaa").wrapInAnyVaultItem(searchableLevel: .onlyPassphrase).makeWritable(),
            anySecureNote(contents: "aaa").wrapInAnyVaultItem(searchableLevel: .none).makeWritable(),
        ]

        for code in codes {
            try await sut.insert(item: code)
        }

        let query = VaultStoreQuery(filterText: "a")
        let result = try await sut.retrieve(query: query)
        #expect(result.items.isEmpty, "Cannot search note content in this state")
        #expect(result.errors == [])
    }

    @Test
    func retrieveMatchingQuery_returnsNoteContentsIfEnabled() async throws {
        let codes: [VaultItem.Write] = [
            anySecureNote(contents: "aaa").wrapInAnyVaultItem(searchableLevel: .onlyTitle).makeWritable(),
            anySecureNote(contents: "aaa").wrapInAnyVaultItem(searchableLevel: .onlyPassphrase).makeWritable(),
            anySecureNote(contents: "aaa").wrapInAnyVaultItem(searchableLevel: .full).makeWritable(),
        ]
        for code in codes {
            try await sut.insert(item: code)
        }

        let query = VaultStoreQuery(filterText: "a")
        let result = try await sut.retrieve(query: query)
        #expect(result.items.count == 1, "Only 1 note matches will full search")
        #expect(result.errors == [])
    }

    @Test
    func retrieveMatchingQuery_doesNotSearchContentsIfLocked() async throws {
        let codes: [VaultItem.Write] = [
            anySecureNote(contents: "aaa").wrapInAnyVaultItem(lockState: .notLocked).makeWritable(),
            anySecureNote(contents: "aaa").wrapInAnyVaultItem(lockState: .lockedWithNativeSecurity).makeWritable(),
            anySecureNote(contents: "aaa").wrapInAnyVaultItem(lockState: .lockedWithNativeSecurity).makeWritable(),
        ]
        for code in codes {
            try await sut.insert(item: code)
        }

        let query = VaultStoreQuery(filterText: "a")
        let result = try await sut.retrieve(query: query)
        #expect(result.items.count == 1, "Only 1 note matches due to 2 items locked")
        #expect(result.errors == [])
    }

    @Test
    func retrieveMatchingQuery_doesSearchTitleIfLocked() async throws {
        let codes: [VaultItem.Write] = [
            anySecureNote(title: "aaa").wrapInAnyVaultItem(lockState: .notLocked).makeWritable(),
            anySecureNote(title: "aaa").wrapInAnyVaultItem(lockState: .lockedWithNativeSecurity).makeWritable(),
            anySecureNote(title: "aaa").wrapInAnyVaultItem(lockState: .lockedWithNativeSecurity).makeWritable(),
        ]
        for code in codes {
            try await sut.insert(item: code)
        }

        let query = VaultStoreQuery(filterText: "a")
        let result = try await sut.retrieve(query: query)
        #expect(result.items.count == 3, "All 3 items returned, regardless of lock state")
        #expect(result.errors == [])
    }

    @Test
    func retrieveMatchingQuery_returnsItemsSearchingByTitle() async throws {
        let codes: [VaultItem.Write] = [
            anySecureNote(title: "aaa").wrapInAnyVaultItem(searchableLevel: .onlyTitle).makeWritable(),
            anyOTPAuthCode(accountName: "aaa").wrapInAnyVaultItem(searchableLevel: .onlyTitle).makeWritable(),
        ]
        for code in codes {
            try await sut.insert(item: code)
        }

        let query = VaultStoreQuery(filterText: "a")
        let result = try await sut.retrieve(query: query)
        #expect(result.items.count == 2, "All items here should be matched")
        #expect(result.errors == [])
    }

    @Test
    func retrieveMatchingQuery_titleOnlyMatchesOTPFields() async throws {
        let codes: [VaultItem.Write] = [
            anyOTPAuthCode(accountName: "aaa").wrapInAnyVaultItem(searchableLevel: .onlyTitle).makeWritable(),
            anyOTPAuthCode(issuerName: "aaabbb").wrapInAnyVaultItem(searchableLevel: .onlyTitle).makeWritable(),
        ]
        var insertedIDs = [Identifier<VaultItem>]()
        for code in codes {
            let id = try await sut.insert(item: code)
            insertedIDs.append(id)
        }

        let query = VaultStoreQuery(filterText: "a")
        let result = try await sut.retrieve(query: query)
        #expect(result.items.map(\.metadata.id) == [insertedIDs[0], insertedIDs[1]], "Matches both")
        #expect(result.errors == [])
    }

    @Test
    func retrieveMatchingQuery_requiresExactPassphraseMatchCaseInsensitive() async throws {
        let digester = SearchPassphraseDigester(key: .zero())
        let codes: [VaultItem.Write] = [
            anySecureNote(title: "aaa").wrapInAnyVaultItem(
                searchableLevel: .onlyPassphrase,
                searchPassphrase: digester.makeDigest(phrase: "n"),
            ).makeWritable(),
            anySecureNote(title: "aaa").wrapInAnyVaultItem(
                searchableLevel: .onlyPassphrase,
                searchPassphrase: digester.makeDigest(phrase: "N"),
            ).makeWritable(),
            anyOTPAuthCode(accountName: "aaa").wrapInAnyVaultItem(
                searchableLevel: .onlyPassphrase,
                searchPassphrase: digester.makeDigest(phrase: "nn"),
            ).makeWritable(),
            anyOTPAuthCode(issuerName: "aaa").wrapInAnyVaultItem(
                searchableLevel: .onlyPassphrase,
                searchPassphrase: digester.makeDigest(phrase: "nnn"),
            ).makeWritable(),
        ]
        var insertedIDs = [Identifier<VaultItem>]()
        for code in codes {
            let id = try await sut.insert(item: code)
            insertedIDs.append(id)
        }

        let query = VaultStoreQuery(filterText: "n")
        let result = try await sut.retrieve(query: query, searchPassphraseMatcher: digester)
        #expect(
            Set(result.items.map(\.metadata.id)) == Set([insertedIDs[0], insertedIDs[1]]),
            "Both items match — passphrase comparison is case-insensitive",
        )
        #expect(result.errors == [])
    }

    @Test
    func retrieveMatchingQuery_returnsPassphraseMatches() async throws {
        let digester = SearchPassphraseDigester(key: .zero())
        let codes: [VaultItem.Write] = [
            anySecureNote(title: "aaa").wrapInAnyVaultItem(searchableLevel: .full).makeWritable(),
            anySecureNote(title: "aaa").wrapInAnyVaultItem(
                searchableLevel: .onlyPassphrase,
                searchPassphrase: digester.makeDigest(phrase: "a"),
            ).makeWritable(),
            anyOTPAuthCode(accountName: "aaa").wrapInAnyVaultItem(
                searchableLevel: .onlyPassphrase,
                searchPassphrase: digester.makeDigest(phrase: "b"),
            ).makeWritable(),
            anyOTPAuthCode(accountName: "aaa").wrapInAnyVaultItem(
                searchableLevel: .onlyPassphrase,
                searchPassphrase: digester.makeDigest(phrase: "q"),
            ).makeWritable(),
        ]
        var insertedIDs = [Identifier<VaultItem>]()
        for code in codes {
            let id = try await sut.insert(item: code)
            insertedIDs.append(id)
        }

        let query = VaultStoreQuery(filterText: "a")
        let result = try await sut.retrieve(query: query, searchPassphraseMatcher: digester)
        #expect(
            Set(result.items.map(\.metadata.id)) == Set([insertedIDs[0], insertedIDs[1]]),
            "Matches first on text, second on passphrase",
        )
        #expect(result.errors == [])
    }

    @Test
    func retrieveMatchingQuery_returnsCorruptedItemsAsErrors() async throws {
        let codes: [VaultItem.Write] = [
            anyOTPAuthCode(accountName: "aaa").wrapInAnyVaultItem().makeWritable(),
            anyOTPAuthCode(accountName: "aaa").wrapInAnyVaultItem().makeWritable(),
            anyOTPAuthCode(accountName: "bbb").wrapInAnyVaultItem().makeWritable(), // not included
            anyOTPAuthCode(accountName: "aaa").wrapInAnyVaultItem().makeWritable(),
        ]
        var ids = [Identifier<VaultItem>]()
        for code in codes {
            let id = try await sut.insert(item: code)
            ids.append(id)
        }

        // Introduce a corruption error on the first item
        try await sut.corruptItemAlgorithm(id: ids[0])

        let query = VaultStoreQuery(filterText: "a")
        let result = try await sut.retrieve(query: query)
        #expect(result.items.map(\.id) == [ids[1], ids[3]])
        #expect(result.errors == [.failedToDecode(.invalidAlgorithm)])
    }

    @Test
    func retrieveMatchingQuery_returnsAllItemsCorrupted() async throws {
        let codes: [VaultItem.Write] = [
            anyOTPAuthCode(accountName: "aaa").wrapInAnyVaultItem().makeWritable(),
            anyOTPAuthCode(accountName: "aaa").wrapInAnyVaultItem().makeWritable(),
            anyOTPAuthCode(accountName: "bbb").wrapInAnyVaultItem().makeWritable(), // not included
            anyOTPAuthCode(accountName: "aaa").wrapInAnyVaultItem().makeWritable(),
        ]
        for code in codes {
            let id = try await sut.insert(item: code)
            // Corrupt all items
            try await sut.corruptItemAlgorithm(id: id)
        }

        let query = VaultStoreQuery(filterText: "a")
        let result = try await sut.retrieve(query: query)
        #expect(result.items == [])
        #expect(result.errors == [
            .failedToDecode(.invalidAlgorithm),
            .failedToDecode(.invalidAlgorithm),
            .failedToDecode(.invalidAlgorithm),
        ])
    }

    @Test
    func retrieveMatchingTags_returnsMatchingAllItemsIfTagNotSpecified() async throws {
        let tag1 = try await sut.insertTag(item: anyVaultItemTag().makeWritable())

        let codes: [VaultItem.Write] = [
            anyOTPAuthCode().wrapInAnyVaultItem(tags: [tag1]).makeWritable(),
            anyOTPAuthCode().wrapInAnyVaultItem(tags: [tag1]).makeWritable(),
        ]
        var insertedIDs = [Identifier<VaultItem>]()
        for code in codes {
            let id = try await sut.insert(item: code)
            insertedIDs.append(id)
        }

        let query = VaultStoreQuery()
        let result = try await sut.retrieve(query: query)
        #expect(result.items.map(\.metadata.id) == [insertedIDs[0], insertedIDs[1]], "Returns both")
        #expect(result.errors == [])
    }

    @Test
    func retrieveMatchingTags_returnsMatchingAllTags() async throws {
        let tag1 = try await sut.insertTag(item: anyVaultItemTag().makeWritable())

        let codes: [VaultItem.Write] = [
            anyOTPAuthCode().wrapInAnyVaultItem(tags: [tag1]).makeWritable(),
            anyOTPAuthCode().wrapInAnyVaultItem(tags: [tag1]).makeWritable(),
            anySecureNote().wrapInAnyVaultItem(tags: [tag1]).makeWritable(),
            anyEncryptedItem().wrapInAnyVaultItem(tags: [tag1]).makeWritable(),
        ]
        var insertedIDs = [Identifier<VaultItem>]()
        for code in codes {
            let id = try await sut.insert(item: code)
            insertedIDs.append(id)
        }

        let query = VaultStoreQuery(filterTags: [tag1])
        let result = try await sut.retrieve(query: query)
        #expect(result.items.map(\.metadata.id) == insertedIDs)
        #expect(result.errors == [])
    }

    @Test
    func retrieveMatchingTags_returnsMatchingTags_ANDSemantics() async throws {
        let tag1 = try await sut.insertTag(item: anyVaultItemTag().makeWritable())
        let tag2 = try await sut.insertTag(item: anyVaultItemTag().makeWritable())

        let codes: [VaultItem.Write] = [
            anyOTPAuthCode().wrapInAnyVaultItem(tags: [tag1]).makeWritable(),
            anyOTPAuthCode().wrapInAnyVaultItem(tags: [tag1, tag2]).makeWritable(),
        ]
        var insertedIDs = [Identifier<VaultItem>]()
        for code in codes {
            let id = try await sut.insert(item: code)
            insertedIDs.append(id)
        }

        let query1 = VaultStoreQuery(filterTags: [tag1])
        let result1 = try await sut.retrieve(query: query1)
        #expect(result1.items.count == 2)
        #expect(result1.errors == [])

        let query2 = VaultStoreQuery(filterTags: [tag1, tag2])
        let result2 = try await sut.retrieve(query: query2)
        #expect(result2.items.map(\.metadata.id) == [insertedIDs[1]])
        #expect(result2.errors == [])
    }

    @Test
    func retrieveMatchingTags_returnsLimitedItemsMatchingTags() async throws {
        let tag1 = try await sut.insertTag(item: anyVaultItemTag().makeWritable())
        let tag2 = try await sut.insertTag(item: anyVaultItemTag().makeWritable())

        let codes: [VaultItem.Write] = [
            anyOTPAuthCode().wrapInAnyVaultItem(tags: [tag1]).makeWritable(),
            anyOTPAuthCode().wrapInAnyVaultItem(tags: [tag2]).makeWritable(),
            anyOTPAuthCode().wrapInAnyVaultItem(tags: [tag1]).makeWritable(),
            anyOTPAuthCode().wrapInAnyVaultItem(tags: [tag2]).makeWritable(),
        ]
        var insertedIDs = [Identifier<VaultItem>]()
        for code in codes {
            let id = try await sut.insert(item: code)
            insertedIDs.append(id)
        }

        let query = VaultStoreQuery(filterTags: [tag1])
        let result = try await sut.retrieve(query: query)
        #expect(result.items.map(\.metadata.id) == [insertedIDs[0], insertedIDs[2]], "Matches both")
        #expect(result.errors == [])
    }

    @Test
    func retrieveMatchingTags_returnsLimitedItemsMatchingTagsMultiple() async throws {
        let tag1 = try await sut.insertTag(item: anyVaultItemTag().makeWritable())
        let tag2 = try await sut.insertTag(item: anyVaultItemTag().makeWritable())
        let codes: [VaultItem.Write] = [
            anyOTPAuthCode().wrapInAnyVaultItem(tags: [tag1, tag2]).makeWritable(),
            anyOTPAuthCode().wrapInAnyVaultItem(tags: [tag2]).makeWritable(),
            anyOTPAuthCode().wrapInAnyVaultItem(tags: [tag1, tag2]).makeWritable(),
            anyOTPAuthCode().wrapInAnyVaultItem(tags: [tag2]).makeWritable(),
        ]
        var insertedIDs = [Identifier<VaultItem>]()
        for code in codes {
            let id = try await sut.insert(item: code)
            insertedIDs.append(id)
        }

        let query = VaultStoreQuery(filterTags: [tag1])
        let result = try await sut.retrieve(query: query)
        #expect(result.items.map(\.metadata.id) == [insertedIDs[0], insertedIDs[2]], "Matches both")
        #expect(result.errors == [])
    }

    @Test
    func hasAnyItems_isFalseForNoItems() async throws {
        let value = try await sut.hasAnyItems

        #expect(value == false)
    }

    @Test
    func hasAnyItems_returnsTrueForSingleItem() async throws {
        let code = anyOTPAuthCode().wrapInAnyVaultItem().makeWritable()
        try await sut.insert(item: code)

        let value = try await sut.hasAnyItems

        #expect(value == true)
    }

    @Test
    func hasAnyItems_returnsTrueForSingleLockedItem() async throws {
        let code = anyOTPAuthCode().wrapInAnyVaultItem(visibility: .onlySearch, searchableLevel: .none).makeWritable()
        try await sut.insert(item: code)

        #expect(try await sut.hasAnyItems)
    }

    @Test
    func insert_deliversNoErrorOnEmptyStore() async throws {
        try await sut.insert(item: uniqueVaultItem().makeWritable())
    }

    @Test
    func insert_deliversNoErrorOnNonEmptyStore() async throws {
        try await sut.insert(item: uniqueVaultItem().makeWritable())
        try await sut.insert(item: uniqueVaultItem().makeWritable())
    }

    @Test
    func insert_doesNotOverrideExactSameEntryAsUsesNewIDToUnique() async throws {
        let code = uniqueVaultItem().makeWritable()

        try await sut.insert(item: code)
        try await sut.insert(item: code)

        let result = try await sut.retrieve(query: .init())
        #expect(result.items.map(\.item.otpCode) == [code.item.otpCode, code.item.otpCode])
        #expect(result.errors == [])
    }

    @Test
    func insert_returnsUniqueCodeIDAfterSuccessfulInsert() async throws {
        let code = uniqueVaultItem().makeWritable()

        var ids = [Identifier<VaultItem>]()
        for _ in 0 ..< 5 {
            let id = try await sut.insert(item: code)
            ids.append(id)
        }

        let result = try await sut.retrieve(query: .init())
        #expect(result.items.map(\.id) == ids)
        #expect(result.errors == [])
    }

    @Test
    func insert_defaultRelativeOrderIsZero() async throws {
        let code = uniqueVaultItem().makeWritable()

        try await sut.insert(item: code)

        let result = try await sut.retrieve(query: .init())
        #expect(result.items.first?.metadata.relativeOrder == 0)
    }

    @Test
    func deleteByID_hasNoEffectOnEmptyStore() async throws {
        try await sut.delete(id: .new())

        let result = try await sut.retrieve(query: .init())
        #expect(result.items == [])
        #expect(result.errors == [])
    }

    @Test
    func deleteByID_deletesSingleEntryMatchingID() async throws {
        let code = uniqueVaultItem().makeWritable()

        let id = try await sut.insert(item: code)

        try await sut.delete(id: id)

        let result = try await sut.retrieve(query: .init())
        #expect(result.items == [])
        #expect(result.errors == [])
    }

    @Test
    func deleteByID_hasNoEffectOnNoMatchingCode() async throws {
        let otherCodes = [
            uniqueVaultItem().makeWritable(),
            uniqueVaultItem().makeWritable(),
            uniqueVaultItem().makeWritable(),
        ]
        for code in otherCodes {
            try await sut.insert(item: code)
        }

        try await sut.delete(id: Identifier<VaultItem>())

        let result = try await sut.retrieve(query: .init())
        #expect(result.items.map(\.item.otpCode) == otherCodes.map(\.item.otpCode))
        #expect(result.errors == [])
    }

    @Test
    func updateByID_deliversErrorIfCodeDoesNotAlreadyExist() async throws {
        await #expect(throws: (any Error).self) {
            try await sut.update(id: Identifier<VaultItem>(), item: uniqueVaultItem().makeWritable())
        }
    }

    @Test
    func updateByID_hasNoEffectOnEmptyStorageIfCodeDoesNotAlreadyExist() async throws {
        try? await sut.update(id: Identifier<VaultItem>(), item: uniqueVaultItem().makeWritable())

        let result = try await sut.retrieve(query: .init())
        #expect(result.items == [])
        #expect(result.errors == [])
    }

    @Test
    func updateByID_hasNoEffectOnNonEmptyStorageIfCodeDoesNotAlreadyExist() async throws {
        let codes = [
            uniqueVaultItem().makeWritable(),
            uniqueVaultItem().makeWritable(),
            uniqueVaultItem().makeWritable(),
        ]
        for code in codes {
            try await sut.insert(item: code)
        }

        try? await sut.update(id: Identifier<VaultItem>(), item: uniqueVaultItem().makeWritable())

        let result = try await sut.retrieve(query: .init())
        #expect(result.items.map(\.item.otpCode) == codes.map(\.item.otpCode))
        #expect(result.errors == [])
    }

    @Test
    func updateByID_updatesDataForValidCode() async throws {
        let initialCode = uniqueVaultItem().makeWritable()
        let id = try await sut.insert(item: initialCode)

        let newCode = uniqueVaultItem().makeWritable()
        try await sut.update(id: id, item: newCode)

        let result = try await sut.retrieve(query: .init())
        #expect(
            result.items.map(\.item.otpCode) != [initialCode.item.otpCode],
            "Should be different from old code.",
        )
        #expect(
            result.items.map(\.item.otpCode) == [newCode.item.otpCode],
            "Should be the same as the new code.",
        )
        #expect(result.errors == [])
    }

    @Test
    func updateByID_hasNoSideEffectsOnOtherCodes() async throws {
        let initialCodes = [
            uniqueVaultItem().makeWritable(),
            uniqueVaultItem().makeWritable(),
            uniqueVaultItem().makeWritable(),
        ]
        for code in initialCodes {
            try await sut.insert(item: code)
        }

        let id = try await sut.insert(item: uniqueVaultItem().makeWritable())

        let newCode = uniqueVaultItem().makeWritable()
        try await sut.update(id: id, item: newCode)

        let result = try await sut.retrieve(query: .init())
        #expect(result.items.map(\.item.otpCode) == initialCodes.map(\.item.otpCode) + [newCode.item.otpCode])
        #expect(result.errors == [])
    }

    @Test
    func reorder_emptyItemsHasNoEffectOnEmptyStore() async throws {
        try await sut.reorder(items: [], to: .start)
    }

    @Test
    func reorder_nonEmptyItemsHasNoEffectOnEmptyStore() async throws {
        try await sut.reorder(items: [.init(id: UUID())], to: .start)
    }

    @Test
    func reorder_reorderToAfterThrowsErrorIfItemDoesNotExist() async throws {
        let code = uniqueVaultItem().makeWritable()
        let id = try await sut.insert(item: code)

        await #expect(throws: (any Error).self) {
            try await sut.reorder(
                items: [id],
                to: .after(.init(id: UUID())),
            )
        }
    }

    @Test
    func reorder_reordersAllItemsIfMovingToStart() async throws {
        await sut.updateSortOrder(.relativeOrder)

        let codes = [
            uniqueVaultItem().makeWritable(),
            uniqueVaultItem().makeWritable(),
            uniqueVaultItem().makeWritable(),
        ]
        var insertedIDs = [Identifier<VaultItem>]()
        for code in codes {
            let id = try await sut.insert(item: code)
            // insert the id at the start because when using .relativeOrder, more recently created items are ordered
            // first
            insertedIDs.insert(id, at: 0)
        }

        try await sut.reorder(items: [insertedIDs[2]], to: .start)

        let result = try await sut.retrieve(query: .init())
        #expect(result.items.map(\.metadata.id) == [insertedIDs[2], insertedIDs[0], insertedIDs[1]])
        #expect(result.items.map(\.metadata.relativeOrder) == [0, 1, 2])
        #expect(result.errors == [])
    }

    @Test
    func reorder_reordersAllIfMovingToAfterOtherItem() async throws {
        await sut.updateSortOrder(.relativeOrder)

        let codes = [
            uniqueVaultItem().makeWritable(),
            uniqueVaultItem().makeWritable(),
            uniqueVaultItem().makeWritable(),
        ]
        var insertedIDs = [Identifier<VaultItem>]()
        for code in codes {
            let id = try await sut.insert(item: code)
            // insert the id at the start because when using .relativeOrder, more recently created items are ordered
            // first
            insertedIDs.insert(id, at: 0)
        }

        try await sut.reorder(items: [insertedIDs[0]], to: .after(insertedIDs[1]))

        let result = try await sut.retrieve(query: .init())
        #expect(result.items.map(\.metadata.id) == [insertedIDs[1], insertedIDs[0], insertedIDs[2]])
        #expect(result.items.map(\.metadata.relativeOrder) == [0, 1, 2])
        #expect(result.errors == [])
    }

    @Test
    func exportVault_hasNoSideEffectsOnEmptyVault() async throws {
        _ = try await sut.exportVault(userDescription: "")

        let result = try await sut.retrieve(query: .init())
        #expect(result == .empty())
    }

    @Test
    func exportVault_hasNoSideEffectsOnNonEmptyVault() async throws {
        let initialCodes = [
            uniqueVaultItem().makeWritable(),
            uniqueVaultItem().makeWritable(),
            uniqueVaultItem().makeWritable(),
        ]
        for code in initialCodes {
            try await sut.insert(item: code)
        }

        _ = try await sut.exportVault(userDescription: "my desc")

        let result = try await sut.retrieve(query: .init())
        #expect(result.items.count == 3)
    }

    @Test
    func exportVault_empty() async throws {
        let export = try await sut.exportVault(userDescription: "my description!")

        #expect(export.userDescription == "my description!")
        #expect(export.items == [])
        #expect(export.tags == [])
    }

    @Test
    func exportVault_withContent() async throws {
        let items = [uniqueVaultItem(), uniqueVaultItem(), uniqueVaultItem()]
        var insertedIDs = [Identifier<VaultItem>]()
        for code in items {
            let id = try await sut.insert(item: code.makeWritable())
            insertedIDs.append(id)
        }
        let tags = [anyVaultItemTag(), anyVaultItemTag()]
        var insertedTagIDs = [Identifier<VaultItemTag>]()
        for tag in tags {
            let id = try await sut.insertTag(item: tag.makeWritable())
            insertedTagIDs.append(id)
        }

        let export = try await sut.exportVault(userDescription: "my description")

        #expect(export.userDescription == "my description")
        #expect(export.items.map { $0.makeWritable() } == items.map { $0.makeWritable() })
        #expect(export.items.map(\.id) == insertedIDs)
        #expect(export.tags.map(\.id) == insertedTagIDs)
    }

    @Test
    func retrieveTags_returnsNoTagsIfThereAreNone() async throws {
        let tags = try await sut.retrieveTags()

        #expect(tags == [])
    }

    @Test
    func retrieveTags_returnsMultipleTags() async throws {
        let items = [
            VaultItemTag.Write(name: "any1", color: .tagDefault, iconName: "any"),
            VaultItemTag.Write(name: "any2", color: .tagDefault, iconName: "any"),
            VaultItemTag.Write(name: "any3", color: .tagDefault, iconName: "any"),
        ]
        var insertedIDs = [UUID]()
        for tag in items {
            let id = try await sut.insertTag(item: tag)
            insertedIDs.append(id.id)
        }
        let tags = try await sut.retrieveTags()

        #expect(tags.map(\.id.id) == insertedIDs)
    }

    @Test
    func insertTag_deliversNoErrorOnEmptyStore() async throws {
        try await sut.insertTag(item: anyVaultItemTag().makeWritable())
    }

    @Test
    func insertTag_deliversNoErrorOnNonEmptyStore() async throws {
        try await sut.insertTag(item: anyVaultItemTag().makeWritable())
        try await sut.insertTag(item: anyVaultItemTag().makeWritable())
    }

    @Test
    func insertTag_doesNotOverrideExactSameEntryAsUsesNewIDToUnique() async throws {
        let code = anyVaultItemTag().makeWritable()

        try await sut.insertTag(item: code)
        try await sut.insertTag(item: code)

        let result = try await sut.retrieveTags()
        #expect(result.count == 2)
    }

    @Test
    func insertTag_returnsUniqueCodeIDAfterSuccessfulInsert() async throws {
        let code = anyVaultItemTag().makeWritable()

        var ids = [UUID]()
        for _ in 0 ..< 5 {
            let id = try await sut.insertTag(item: code)
            ids.append(id.id)
        }

        let result = try await sut.retrieveTags()
        #expect(result.map(\.id.id) == ids)
    }

    @Test
    func deleteTag_hasNoEffectOnEmptyStore() async throws {
        try await sut.deleteTag(id: .init(id: UUID()))

        let result = try await sut.retrieveTags()
        #expect(result == [])
    }

    @Test
    func deleteTag_deletesSingleEntryMatchingID() async throws {
        let code = anyVaultItemTag().makeWritable()

        let id = try await sut.insertTag(item: code)

        try await sut.deleteTag(id: id)

        let result = try await sut.retrieveTags()
        #expect(result == [])
    }

    @Test
    func deleteTag_hasNoEffectOnNoMatchingTag() async throws {
        let otherTags = [
            anyVaultItemTag().makeWritable(),
            anyVaultItemTag().makeWritable(),
            anyVaultItemTag().makeWritable(),
        ]
        var insertedIds = [Identifier<VaultItemTag>]()
        for tag in otherTags {
            let id = try await sut.insertTag(item: tag)
            insertedIds.append(id)
        }

        try await sut.deleteTag(id: .init(id: UUID()))

        let result = try await sut.retrieveTags()
        #expect(result.map(\.id) == insertedIds)
    }

    @Test
    func deleteTag_removesFromModels() async throws {
        let otherTags = [
            anyVaultItemTag().makeWritable(),
            anyVaultItemTag().makeWritable(),
            anyVaultItemTag().makeWritable(),
        ]
        var insertedTagIds = [Identifier<VaultItemTag>]()
        for tag in otherTags {
            let id = try await sut.insertTag(item: tag)
            insertedTagIds.append(id)
        }

        let item1 = uniqueVaultItem(tags: insertedTagIds.reducedToSet()).makeWritable()
        let item2 = uniqueVaultItem(tags: [insertedTagIds[1], insertedTagIds[2]]).makeWritable()

        try await sut.insert(item: item1)
        try await sut.insert(item: item2)

        try await sut.deleteTag(id: insertedTagIds[0])

        let result = try await sut.retrieve(query: .init())
        let firstItem = result.items[0]
        #expect(firstItem.metadata.tags == [insertedTagIds[1], insertedTagIds[2]])
        let secondItem = result.items[1]
        #expect(secondItem.metadata.tags == [insertedTagIds[1], insertedTagIds[2]])
    }

    @Test
    func updateTag_deliversErrorIfCodeDoesNotAlreadyExist() async throws {
        await #expect(throws: (any Error).self) {
            try await sut.updateTag(id: .init(id: UUID()), item: anyVaultItemTag().makeWritable())
        }
    }

    @Test
    func updateTag_hasNoEffectOnEmptyStorageIfDoesNotAlreadyExist() async throws {
        await #expect(throws: (any Error).self) {
            try await sut.updateTag(id: .init(id: UUID()), item: anyVaultItemTag().makeWritable())
        }

        let result = try await sut.retrieveTags()
        #expect(result == [])
    }

    @Test
    func updateTag_hasNoEffectOnNonEmptyStorageIfDoesNotAlreadyExist() async throws {
        let tags = [
            anyVaultItemTag().makeWritable(),
            anyVaultItemTag().makeWritable(),
            anyVaultItemTag().makeWritable(),
        ]
        for tag in tags {
            try await sut.insertTag(item: tag)
        }

        await #expect(throws: (any Error).self) {
            try await sut.updateTag(id: .init(id: UUID()), item: anyVaultItemTag().makeWritable())
        }

        let result = try await sut.retrieveTags()
        #expect(result.map { $0.makeWritable() } == tags)
    }

    @Test
    func updateTag_updatesDataForValidTag() async throws {
        let initial = anyVaultItemTag().makeWritable()
        let id = try await sut.insertTag(item: initial)

        let newTag = anyVaultItemTag(name: "this is the new name").makeWritable()
        try await sut.updateTag(id: id, item: newTag)

        let result = try await sut.retrieveTags()
        #expect(result.map(\.name) == ["this is the new name"])
    }

    @Test
    func updateTag_hasNoSideEffectsOnOtherTags() async throws {
        let initialTags = [
            anyVaultItemTag().makeWritable(),
            anyVaultItemTag().makeWritable(),
            anyVaultItemTag().makeWritable(),
        ]
        var insertedIds = [Identifier<VaultItemTag>]()
        for tag in initialTags {
            let id = try await sut.insertTag(item: tag)
            insertedIds.append(id)
        }

        let id = try await sut.insertTag(item: anyVaultItemTag().makeWritable())

        let newTag = anyVaultItemTag().makeWritable()
        try await sut.updateTag(id: id, item: newTag)

        let result = try await sut.retrieveTags()
        #expect(result.map(\.id) == insertedIds + [id])
    }

    @Test
    func deleteVault_hasNoEffectOnEmptyStore() async throws {
        try await sut.deleteVault()

        try await assertStoreEmpty()
    }

    @Test
    func deleteVault_removesAllItems() async throws {
        let tag1 = try await sut.insertTag(item: anyVaultItemTag().makeWritable())
        let tag2 = try await sut.insertTag(item: anyVaultItemTag().makeWritable())
        let codes: [VaultItem.Write] = [
            anyOTPAuthCode().wrapInAnyVaultItem(tags: [tag1, tag2]).makeWritable(),
            anyOTPAuthCode().wrapInAnyVaultItem(tags: [tag2]).makeWritable(),
            anyOTPAuthCode().wrapInAnyVaultItem(tags: [tag1, tag2]).makeWritable(),
            anyOTPAuthCode().wrapInAnyVaultItem(tags: [tag2]).makeWritable(),
        ]
        for code in codes {
            try await sut.insert(item: code)
        }

        try await sut.deleteVault()

        try await assertStoreEmpty()
    }

    @Test
    func incrementCounter_throwsForNonTOTP() async throws {
        let note = anySecureNote().wrapInAnyVaultItem().makeWritable()
        let id1 = try await sut.insert(item: note)

        await #expect(throws: (any Error).self) {
            try await sut.incrementCounter(id: id1)
        }
    }

    @Test
    func incrementCounter_incrementsHOTP() async throws {
        let code = anyOTPAuthCode(type: .hotp(counter: 12)).wrapInAnyVaultItem().makeWritable()
        let id1 = try await sut.insert(item: code)

        try await sut.incrementCounter(id: id1)

        let all = try await sut.retrieve(query: .init())
        let item = try #require(all.items.first)
        switch item.item.otpCode?.type {
        case let .hotp(counter): #expect(counter == 13)
        default: Issue.record("Expected hotp")
        }
    }

    @Test
    func importAndMergeVault_importsEmptyToEmptyVault() async throws {
        let payload = VaultApplicationPayload(userDescription: "", items: [], tags: [])

        try await sut.importAndMergeVault(payload: payload)

        try await assertStoreEmpty()
    }

    @Test
    func importAndMergeVault_emptyToNonEmptyVault() async throws {
        let item1 = uniqueVaultItem(updatedDate: Date(timeIntervalSince1970: 50))
        let item2 = uniqueVaultItem(updatedDate: Date(timeIntervalSince1970: 100))
        let item3 = uniqueVaultItem(updatedDate: Date(timeIntervalSince1970: 200))
        let items = [item1, item2, item3]
        let tag1 = anyVaultItemTag(name: "A")
        let tag2 = anyVaultItemTag(name: "B")
        let tags = [tag1, tag2]
        let payload1 = VaultApplicationPayload(
            userDescription: "Hello world",
            items: items,
            tags: tags,
        )

        try await sut.importAndMergeVault(payload: payload1)

        let payload2 = VaultApplicationPayload(userDescription: "", items: [], tags: [])
        try await sut.importAndMergeVault(payload: payload2)

        try await assertStoreContains(exactlyItems: items)
        try await assertStoreContains(exactlyTags: tags)
    }

    @Test
    func importAndMergeVault_importsNonEmptyToEmptyVault() async throws {
        let item1 = uniqueVaultItem(updatedDate: Date(timeIntervalSince1970: 50))
        let item2 = uniqueVaultItem(updatedDate: Date(timeIntervalSince1970: 100))
        let item3 = uniqueVaultItem(updatedDate: Date(timeIntervalSince1970: 200))
        let items = [item1, item2, item3]
        let tag1 = anyVaultItemTag(name: "A")
        let tag2 = anyVaultItemTag(name: "B")
        let tags = [tag1, tag2]
        let payload = VaultApplicationPayload(
            userDescription: "Hello world",
            items: items,
            tags: tags,
        )

        try await sut.importAndMergeVault(payload: payload)

        try await assertStoreContains(exactlyItems: items)
        try await assertStoreContains(exactlyTags: tags)
    }

    @Test
    func importAndMergeVault_importsNonEmptyToNonEmptyVault() async throws {
        let item1 = uniqueVaultItem(updatedDate: Date(timeIntervalSince1970: 50))
        let item2 = uniqueVaultItem(updatedDate: Date(timeIntervalSince1970: 100))
        let item3 = uniqueVaultItem(updatedDate: Date(timeIntervalSince1970: 200))
        let items1 = [item1, item2, item3]
        let tag1 = anyVaultItemTag(name: "A")
        let tag2 = anyVaultItemTag(name: "B")
        let tags1 = [tag1, tag2]
        let payload1 = VaultApplicationPayload(
            userDescription: "Hello world",
            items: items1,
            tags: tags1,
        )

        try await sut.importAndMergeVault(payload: payload1)

        let item_a = uniqueVaultItem(updatedDate: Date(timeIntervalSince1970: 400))
        let item_b = uniqueVaultItem(updatedDate: Date(timeIntervalSince1970: 500))
        let item_c = uniqueVaultItem(updatedDate: Date(timeIntervalSince1970: 600))
        let items2 = [item_a, item_b, item_c]
        let tag_c = anyVaultItemTag(name: "C")
        let tag_d = anyVaultItemTag(name: "D")
        let tags2 = [tag_c, tag_d]
        let payload2 = VaultApplicationPayload(
            userDescription: "Hello world",
            items: items2,
            tags: tags2,
        )

        try await sut.importAndMergeVault(payload: payload2)

        try await assertStoreContains(exactlyItems: items1 + items2)
        try await assertStoreContains(exactlyTags: tags1 + tags2)
    }

    @Test
    func importAndMergeVault_overridesItemWithSameIDAndLaterDate() async throws {
        let id1 = Identifier<VaultItem>.new()
        let item1 = uniqueVaultItem(id: id1, updatedDate: Date(timeIntervalSince1970: 50), userDescription: "ABC")
        let itemX = uniqueVaultItem()
        let id2 = UUID()
        let tag1 = anyVaultItemTag(id: id2, name: "A")
        let tagX = anyVaultItemTag(name: "N")
        let payload1 = VaultApplicationPayload(
            userDescription: "Hello world",
            items: [item1, itemX],
            tags: [tag1, tagX],
        )

        try await sut.importAndMergeVault(payload: payload1)

        let item2 = uniqueVaultItem(id: id1, updatedDate: Date(timeIntervalSince1970: 60), userDescription: "DEF")
        let tag2 = anyVaultItemTag(id: id2, name: "B")
        let payload2 = VaultApplicationPayload(
            userDescription: "Hello world",
            items: [item2],
            tags: [tag2],
        )

        try await sut.importAndMergeVault(payload: payload2)

        try await assertStoreContains(exactlyItems: [item2, itemX])
        try await assertStoreContains(exactlyTags: [tag2, tagX])
    }

    @Test
    func importAndMergeVault_retainsExistingItemWithLaterUpdatedDate() async throws {
        let id1 = Identifier<VaultItem>.new()
        let item1 = uniqueVaultItem(id: id1, updatedDate: Date(timeIntervalSince1970: 60), userDescription: "ABC")
        let itemX = uniqueVaultItem()
        let id2 = UUID()
        let tag1 = anyVaultItemTag(id: id2, name: "A")
        let tagX = anyVaultItemTag(name: "N")
        let payload1 = VaultApplicationPayload(
            userDescription: "Hello world",
            items: [item1, itemX],
            tags: [tag1, tagX],
        )

        try await sut.importAndMergeVault(payload: payload1)

        let item2 = uniqueVaultItem(id: id1, updatedDate: Date(timeIntervalSince1970: 50), userDescription: "DEF")
        let tag2 = anyVaultItemTag(id: id2, name: "B")
        let payload2 = VaultApplicationPayload(
            userDescription: "Hello world",
            items: [item2],
            tags: [tag2],
        )

        try await sut.importAndMergeVault(payload: payload2)

        try await assertStoreContains(exactlyItems: [item1, itemX])
        try await assertStoreContains(
            exactlyTags: [tag2, tagX],
            message: "Tag is always updated, there is no date there.",
        )
    }

    @Test
    func importAndOverrideVault_importsEmptyToEmptyVault() async throws {
        let payload = VaultApplicationPayload(userDescription: "", items: [], tags: [])

        try await sut.importAndOverrideVault(payload: payload)

        try await assertStoreEmpty()
    }

    @Test
    func importAndOverrideVault_importsEmptyToNonEmptyVault() async throws {
        let item1 = uniqueVaultItem(updatedDate: Date(timeIntervalSince1970: 50))
        let item2 = uniqueVaultItem(updatedDate: Date(timeIntervalSince1970: 100))
        let item3 = uniqueVaultItem(updatedDate: Date(timeIntervalSince1970: 200))
        let items = [item1, item2, item3]
        let tag1 = anyVaultItemTag(name: "A")
        let tag2 = anyVaultItemTag(name: "B")
        let tags = [tag1, tag2]
        let payload1 = VaultApplicationPayload(
            userDescription: "Hello world",
            items: items,
            tags: tags,
        )

        try await sut.importAndMergeVault(payload: payload1)

        let payload2 = VaultApplicationPayload(userDescription: "", items: [], tags: [])

        try await sut.importAndOverrideVault(payload: payload2)

        try await assertStoreEmpty()
    }

    @Test
    func importAndOverrideVault_importsNonEmptyToEmptyVault() async throws {
        let item1 = uniqueVaultItem(updatedDate: Date(timeIntervalSince1970: 50))
        let item2 = uniqueVaultItem(updatedDate: Date(timeIntervalSince1970: 100))
        let item3 = uniqueVaultItem(updatedDate: Date(timeIntervalSince1970: 200))
        let items = [item1, item2, item3]
        let tag1 = anyVaultItemTag(name: "A")
        let tag2 = anyVaultItemTag(name: "B")
        let tags = [tag1, tag2]
        let payload1 = VaultApplicationPayload(
            userDescription: "Hello world",
            items: items,
            tags: tags,
        )

        try await sut.importAndOverrideVault(payload: payload1)

        try await assertStoreContains(exactlyItems: items)
        try await assertStoreContains(exactlyTags: tags)
    }

    @Test
    func importAndOverrideVault_overridesExistingDataWithNew() async throws {
        let item1 = uniqueVaultItem(updatedDate: Date(timeIntervalSince1970: 50))
        let item2 = uniqueVaultItem(updatedDate: Date(timeIntervalSince1970: 100))
        let item3 = uniqueVaultItem(updatedDate: Date(timeIntervalSince1970: 200))
        let items = [item1, item2, item3]
        let tag1 = anyVaultItemTag(name: "A")
        let tag2 = anyVaultItemTag(name: "B")
        let tags = [tag1, tag2]
        let payload1 = VaultApplicationPayload(
            userDescription: "Hello world",
            items: items,
            tags: tags,
        )

        try await sut.importAndOverrideVault(payload: payload1)

        let item4 = uniqueVaultItem(updatedDate: Date(timeIntervalSince1970: 50))
        let item5 = uniqueVaultItem(updatedDate: Date(timeIntervalSince1970: 100))
        let item6 = uniqueVaultItem(updatedDate: Date(timeIntervalSince1970: 200))
        let items2 = [item4, item5, item6]
        let tag4 = anyVaultItemTag(name: "C")
        let tag5 = anyVaultItemTag(name: "D")
        let tags2 = [tag4, tag5]
        let payload2 = VaultApplicationPayload(
            userDescription: "Hello world",
            items: items2,
            tags: tags2,
        )

        try await sut.importAndOverrideVault(payload: payload2)

        try await assertStoreContains(exactlyItems: items2)
        try await assertStoreContains(exactlyTags: tags2)
    }

    @Test
    func deleteItemsMatchingKillphrase_hasNoEffectIfVaultEmpty() async throws {
        let didDelete = await sut.deleteItems(matchingKillphrase: "a", using: testDigester)

        #expect(didDelete == false)
        try await assertStoreContains(exactlyItems: [])
    }

    @Test
    func deleteItemsMatchingKillphrase_deletesSingleItem() async throws {
        let item1 = uniqueVaultItem(killphrase: "a")
        let item2 = uniqueVaultItem(killphrase: "b")
        let item3 = uniqueVaultItem(killphrase: "c")
        let items = [item1, item2, item3]
        let payload = VaultApplicationPayload(
            userDescription: "Hello world",
            items: items,
            tags: [],
        )
        try await sut.importAndOverrideVault(payload: payload)

        let didDelete = await sut.deleteItems(matchingKillphrase: "a", using: testDigester)

        #expect(didDelete == true)
        try await assertStoreContains(exactlyItems: [item2, item3])
    }

    @Test
    func deleteItemsMatchingKillphrase_deletesMultipleItems() async throws {
        let item1 = uniqueVaultItem(killphrase: "a")
        let item2 = uniqueVaultItem(killphrase: "a")
        let item3 = uniqueVaultItem(killphrase: "b")
        let items = [item1, item2, item3]
        let payload = VaultApplicationPayload(
            userDescription: "Hello world",
            items: items,
            tags: [],
        )
        try await sut.importAndOverrideVault(payload: payload)

        let didDelete = await sut.deleteItems(matchingKillphrase: "a", using: testDigester)

        #expect(didDelete == true)
        try await assertStoreContains(exactlyItems: [item3])
    }

    @Test
    func deleteItemsMatchingKillphrase_deletesExactMatchOnly() async throws {
        let item1 = uniqueVaultItem(killphrase: "a")
        let item2 = uniqueVaultItem(killphrase: "aa")
        let item3 = uniqueVaultItem(killphrase: "aaa")
        let items = [item1, item2, item3]
        let payload = VaultApplicationPayload(
            userDescription: "Hello world",
            items: items,
            tags: [],
        )
        try await sut.importAndOverrideVault(payload: payload)

        let didDelete = await sut.deleteItems(matchingKillphrase: "a", using: testDigester)

        #expect(didDelete == true)
        try await assertStoreContains(exactlyItems: [item2, item3])
    }

    @Test
    func deleteItemsMatchingKillphrase_matchesQueryWithSurroundingWhitespace() async throws {
        let item1 = uniqueVaultItem(killphrase: "phrase")
        let item2 = uniqueVaultItem(killphrase: "other")
        let payload = VaultApplicationPayload(
            userDescription: "Hello world",
            items: [item1, item2],
            tags: [],
        )
        try await sut.importAndOverrideVault(payload: payload)

        // The search bar delivers untrimmed text; a trailing space must
        // not stop the killphrase firing.
        let didDelete = await sut.deleteItems(matchingKillphrase: "phrase ", using: testDigester)

        #expect(didDelete == true)
        try await assertStoreContains(exactlyItems: [item2])
    }

    @Test
    func deleteItemsMatchingKillphrase_doesNotDeleteEmptyKillphraseItems() async throws {
        let item1 = uniqueVaultItem(killphrase: nil)
        let item2 = uniqueVaultItem(killphrase: "a")
        let item3 = uniqueVaultItem(killphrase: "")
        let items = [item1, item2, item3]
        let payload = VaultApplicationPayload(
            userDescription: "Hello world",
            items: items,
            tags: [],
        )
        try await sut.importAndOverrideVault(payload: payload)

        let didDelete = await sut.deleteItems(matchingKillphrase: "a", using: testDigester)

        #expect(didDelete == true)
        try await assertStoreContains(exactlyItems: [item1, item3])
    }

    @Test
    func deleteItemsMatchingKillphrase_doesNotDeleteAnyItemsIfPhraseIsBlank() async throws {
        let item1 = uniqueVaultItem(killphrase: nil)
        let item2 = uniqueVaultItem(killphrase: "a")
        let item3 = uniqueVaultItem(killphrase: "")
        let items = [item1, item2, item3]
        let payload = VaultApplicationPayload(
            userDescription: "Hello world",
            items: items,
            tags: [],
        )

        try await sut.importAndOverrideVault(payload: payload)

        let emptyDidDelete = await sut.deleteItems(matchingKillphrase: "", using: testDigester)
        let spaceDidDelete = await sut.deleteItems(matchingKillphrase: " ", using: testDigester)
        let spacesDidDelete = await sut.deleteItems(matchingKillphrase: "       ", using: testDigester)
        let newlineDidDelete = await sut.deleteItems(matchingKillphrase: "\n", using: testDigester)

        #expect(emptyDidDelete == false)
        #expect(spaceDidDelete == false)
        #expect(spacesDidDelete == false)
        #expect(newlineDidDelete == false)
        try await assertStoreContains(exactlyItems: [item1, item2, item3])
    }
}

// MARK: - Helpers

extension PersistedLocalVaultStoreTests {
    private func assertStoreContains(
        item: VaultItem,
        file _: StaticString = #filePath,
        line _: UInt = #line,
    ) async throws {
        let allItems = try await sut.allVaultItems()
        let found = try #require(allItems.first(where: { $0.id == item.id }), "Item not in store")
        #expect(found == item)
    }

    private func assertStoreContains(
        exactlyItems: [VaultItem],
        sourceLocation: SourceLocation = #_sourceLocation,
    ) async throws {
        let allItems = try await sut.allVaultItems()
        let actualItems = allItems.sorted(by: { $0.metadata.updated < $1.metadata.updated })
        let expectedItems = exactlyItems.sorted(by: { $0.metadata.updated < $1.metadata.updated })
        #expect(
            actualItems == expectedItems,
            "Store does not contain exactly the specified items.",
            sourceLocation: sourceLocation,
        )
    }

    private func assertStoreContains(
        exactlyTags: [VaultItemTag],
        message _: String? = nil,
        sourceLocation: SourceLocation = #_sourceLocation,
    ) async throws {
        let allItems = try await sut.allVaultTags()
        let actualItems = allItems.sorted(by: { $0.name < $1.name })
        let expectedItems = exactlyTags.sorted(by: { $0.name < $1.name })
        #expect(
            actualItems == expectedItems,
            "Tags not equal",
            sourceLocation: sourceLocation,
        )
    }

    private func assertStoreContains(
        tag: VaultItemTag,
        file _: StaticString = #filePath,
        line _: UInt = #line,
    ) async throws {
        let allItems = try await sut.allVaultTags()
        let found = try #require(allItems.first(where: { $0.id == tag.id }), "Tag not in store")
        #expect(found == tag)
    }

    private func assertStoreEmpty(sourceLocation: SourceLocation = #_sourceLocation) async throws {
        let allItems = try await sut.allVaultItems()
        let allTags = try await sut.allVaultTags()
        #expect(allItems == [], "Store is not empty!", sourceLocation: sourceLocation)
        #expect(allTags == [], "Store is not empty!", sourceLocation: sourceLocation)
    }
}

extension PersistedLocalVaultStore {
    fileprivate func allVaultItems() async throws -> [VaultItem] {
        let descriptor = FetchDescriptor<PersistedVaultItem>(predicate: .true)
        let result = try modelContext.fetch(descriptor)
        let decoder = PersistedVaultItemDecoder()
        return try result.map {
            try decoder.decode(item: $0)
        }
    }

    fileprivate func allVaultTags() async throws -> [VaultItemTag] {
        let descriptor = FetchDescriptor<PersistedVaultTag>(predicate: .true)
        let result = try modelContext.fetch(descriptor)
        let decoder = PersistedVaultTagDecoder()
        return try result.map {
            try decoder.decode(item: $0)
        }
    }

    fileprivate func corruptItemAlgorithm(id: Identifier<VaultItem>) async throws {
        let uuid = id.rawValue
        var descriptor = FetchDescriptor<PersistedVaultItem>(predicate: #Predicate { item in
            item.id == uuid
        })
        descriptor.fetchLimit = 1
        let existing = try #require(try? modelContext.fetch(descriptor).first, "Item not found")
        existing.otpDetails?.algorithm = "INVALID"

        modelContext.insert(existing)
        try modelContext.save()
    }

    func updateSortOrder(_ order: VaultStoreSortOrder) {
        sortOrder = order
    }
}
