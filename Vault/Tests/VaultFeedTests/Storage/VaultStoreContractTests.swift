import Foundation
import FoundationExtensions
import SwiftData
import TestHelpers
import Testing
import VaultCore
@testable import VaultFeed

/// The behavior every vault store must have, run against each store (`VaultStoreEngine`).
///
/// Each test gets a new, empty store sorting by created date, so items come back in the order they were
/// inserted unless the test changes the sort order.
struct VaultStoreContractTests {
    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveAll_deliversEmptyOnEmptyStore(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        let result = try await sut.retrieve(query: .init())
        #expect(result == .empty())
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveAll_hasNoSideEffectsOnEmptyStore(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        let result1 = try await sut.retrieve(query: .init())
        #expect(result1 == .empty())
        let result2 = try await sut.retrieve(query: .init())
        #expect(result2 == .empty())
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveAll_deliversSingleCodeOnNonEmptyStore(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        let code = uniqueVaultItem().makeWritable()
        try await sut.insert(item: code)

        let result = try await sut.retrieve(query: .init())
        #expect(result.items.map(\.item.otpCode) == [code.item.otpCode])
        #expect(result.errors == [])
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveAll_deliversMultipleCodesOnNonEmptyStore(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveAll_hasNoSideEffectsOnNonEmptyStore(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveAll_doesNotReturnSearchOnlyItems(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveAll_returnsAlwaysVisibleItems(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveAll_relativeOrderReturnsItemsInRelativeOrder(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveAll_returnsCorruptedItemsAsErrors(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveAll_returnsAllItemsCorrupted(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveMatchingQuery_returnsEmptyOnEmptyStoreAndEmptyQuery(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        let query = VaultStoreQuery(filterText: "")
        let result = try await sut.retrieve(query: query)
        #expect(result.items == [])
        #expect(result.errors == [])
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveMatchingQuery_returnsEmptyOnEmptyStore(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        let query = VaultStoreQuery(filterText: "any")
        let result = try await sut.retrieve(query: query)
        #expect(result.items == [])
        #expect(result.errors == [])
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveMatchingQuery_hasNoSideEffectsOnEmptyStore(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        let query = VaultStoreQuery(filterText: "any")
        let result1 = try await sut.retrieve(query: query)
        #expect(result1.items == [])
        #expect(result1.errors == [])
        let result2 = try await sut.retrieve(query: query)
        #expect(result2.items == [])
        #expect(result2.errors == [])
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveMatchingQuery_returnsEmptyForNoQueryMatches(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveMatchingQuery_deliversSingleMatchOnMatchingQuery(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveMatchingQuery_hasNoSideEffectsOnSingleMatch(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveMatchingQuery_deliversMultipleMatchesOnMatchingQuery(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveMatchingQuery_matchesUserDescription(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveMatchingQuery_matchesOTPAccountName(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveMatchingQuery_matchesOTPIssuer(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveMatchingQuery_matchesNoteDetailsTitle(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveMatchingQuery_skipsNonSearchableNoteTitle(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveMatchingQuery_matchesNoteDetailsContents(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveMatchingQuery_skipsNonSearchableNoteContents(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveMatchingQuery_matchesEncryptedItemTitle(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveMatchingQuery_skipsNonSearchableEncryptedItemTitles(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveMatchingQuery_filtersByTagsAsWell(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveMatchingQuery_combinesResultsFromDifferentFields(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveMatchingQuery_returnsMatchesForAllQueryStates(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveMatchingQuery_doesNotReturnNotesSearchingByContent(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveMatchingQuery_returnsNoteContentsIfEnabled(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveMatchingQuery_doesNotSearchContentsIfLocked(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveMatchingQuery_doesSearchTitleIfLocked(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveMatchingQuery_returnsItemsSearchingByTitle(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveMatchingQuery_titleOnlyMatchesOTPFields(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveMatchingQuery_requiresExactPassphraseMatchCaseInsensitive(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveMatchingQuery_returnsPassphraseMatches(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveMatchingQuery_keepsOnlyPassphraseItemsHiddenWhenMatcherNil(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        let digester = SearchPassphraseDigester(key: .zero())
        // The hidden item's title matches the text query, so the text
        // predicate alone would leak it if searchableLevel were
        // mishandled. This is the state after a keychain key-load failure
        // leaves the matcher nil — hidden items must fail closed.
        let hiddenID = try await sut.insert(item: anySecureNote(title: "aaa").wrapInAnyVaultItem(
            searchableLevel: .onlyPassphrase,
            searchPassphrase: digester.makeDigest(phrase: "aaa"),
        ).makeWritable())
        let controlID = try await sut.insert(
            item: anySecureNote(title: "aaa").wrapInAnyVaultItem(searchableLevel: .full).makeWritable(),
        )

        let query = VaultStoreQuery(filterText: "aaa")
        let explicitNil = try await sut.retrieve(query: query, searchPassphraseMatcher: nil)
        let convenience = try await sut.retrieve(query: query)

        #expect(explicitNil.items.map(\.metadata.id) == [controlID])
        #expect(convenience.items.map(\.metadata.id) == [controlID])
        #expect(explicitNil.items.map(\.metadata.id).contains(hiddenID) == false)
        #expect(explicitNil.errors == [])
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveMatchingQuery_keepsOnlyPassphraseItemsHiddenForWrongPhrase(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        let digester = SearchPassphraseDigester(key: .zero())
        let hiddenID = try await sut.insert(item: anySecureNote(title: "bbb").wrapInAnyVaultItem(
            searchableLevel: .onlyPassphrase,
            searchPassphrase: digester.makeDigest(phrase: "secret phrase"),
        ).makeWritable())
        let controlID = try await sut.insert(
            item: anySecureNote(title: "bbb").wrapInAnyVaultItem(searchableLevel: .full).makeWritable(),
        )

        let query = VaultStoreQuery(filterText: "bbb")
        let result = try await sut.retrieve(query: query, searchPassphraseMatcher: digester)

        #expect(result.items.map(\.metadata.id) == [controlID])
        #expect(result.items.map(\.metadata.id).contains(hiddenID) == false)
        #expect(result.errors == [])
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveMatchingQuery_returnsCorruptedItemsAsErrors(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveMatchingQuery_returnsAllItemsCorrupted(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveMatchingTags_returnsMatchingAllItemsIfTagNotSpecified(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveMatchingTags_returnsMatchingAllTags(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveMatchingTags_returnsMatchingTags_ANDSemantics(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveMatchingTags_returnsLimitedItemsMatchingTags(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveMatchingTags_returnsLimitedItemsMatchingTagsMultiple(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func hasAnyItems_isFalseForNoItems(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        let value = try await sut.hasAnyItems

        #expect(value == false)
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func hasAnyItems_returnsTrueForSingleItem(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        let code = anyOTPAuthCode().wrapInAnyVaultItem().makeWritable()
        try await sut.insert(item: code)

        let value = try await sut.hasAnyItems

        #expect(value == true)
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func hasAnyItems_returnsTrueForSingleLockedItem(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        let code = anyOTPAuthCode().wrapInAnyVaultItem(visibility: .onlySearch, searchableLevel: .none).makeWritable()
        try await sut.insert(item: code)

        #expect(try await sut.hasAnyItems)
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func insert_deliversNoErrorOnEmptyStore(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        try await sut.insert(item: uniqueVaultItem().makeWritable())
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func insert_deliversNoErrorOnNonEmptyStore(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        try await sut.insert(item: uniqueVaultItem().makeWritable())
        try await sut.insert(item: uniqueVaultItem().makeWritable())
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func insert_doesNotOverrideExactSameEntryAsUsesNewIDToUnique(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        let code = uniqueVaultItem().makeWritable()

        try await sut.insert(item: code)
        try await sut.insert(item: code)

        let result = try await sut.retrieve(query: .init())
        #expect(result.items.map(\.item.otpCode) == [code.item.otpCode, code.item.otpCode])
        #expect(result.errors == [])
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func insert_returnsUniqueCodeIDAfterSuccessfulInsert(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func insert_defaultRelativeOrderIsZero(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        let code = uniqueVaultItem().makeWritable()

        try await sut.insert(item: code)

        let result = try await sut.retrieve(query: .init())
        #expect(result.items.first?.metadata.relativeOrder == 0)
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func insert_keepsOnlyTagsThatAreStored(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        let storedTagID = try await sut.insertTag(item: anyVaultItemTag().makeWritable())
        let missingTagID = Identifier<VaultItemTag>(id: UUID())
        let code = uniqueVaultItem(tags: [storedTagID, missingTagID]).makeWritable()

        try await sut.insert(item: code)

        let result = try await sut.retrieve(query: .init())
        #expect(result.items.map(\.metadata.tags) == [[storedTagID]])
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func deleteByID_hasNoEffectOnEmptyStore(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        try await sut.delete(id: .new())

        let result = try await sut.retrieve(query: .init())
        #expect(result.items == [])
        #expect(result.errors == [])
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func deleteByID_deletesSingleEntryMatchingID(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        let code = uniqueVaultItem().makeWritable()

        let id = try await sut.insert(item: code)

        try await sut.delete(id: id)

        let result = try await sut.retrieve(query: .init())
        #expect(result.items == [])
        #expect(result.errors == [])
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func deleteByID_hasNoEffectOnNoMatchingCode(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func updateByID_deliversErrorIfCodeDoesNotAlreadyExist(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        await #expect(throws: (any Error).self) {
            try await sut.update(id: Identifier<VaultItem>(), item: uniqueVaultItem().makeWritable())
        }
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func updateByID_hasNoEffectOnEmptyStorageIfCodeDoesNotAlreadyExist(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        try? await sut.update(id: Identifier<VaultItem>(), item: uniqueVaultItem().makeWritable())

        let result = try await sut.retrieve(query: .init())
        #expect(result.items == [])
        #expect(result.errors == [])
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func updateByID_hasNoEffectOnNonEmptyStorageIfCodeDoesNotAlreadyExist(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func updateByID_updatesDataForValidCode(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func updateByID_hasNoSideEffectsOnOtherCodes(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func updateByID_keepsDigestsLeftUnchanged(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        let killphrase = KillphraseDigest(salt: .random(count: 16), digest: .random(count: 32))
        let searchPassphrase = SearchPassphraseDigest(salt: .random(count: 16), digest: .random(count: 32))
        var initial = uniqueVaultItem().makeWritable()
        initial.killphraseUpdate = .set(killphrase)
        initial.searchPassphraseUpdate = .set(searchPassphrase)
        let id = try await sut.insert(item: initial)

        var updated = uniqueVaultItem(userDescription: "Updated").makeWritable()
        updated.killphraseUpdate = .unchanged
        updated.searchPassphraseUpdate = .unchanged
        try await sut.update(id: id, item: updated)

        let stored = try #require(try await sut.allVaultItems().first)
        #expect(stored.metadata.userDescription == "Updated")
        #expect(stored.metadata.killphrase == killphrase)
        #expect(stored.metadata.searchPassphrase == searchPassphrase)
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func updateByID_keepsIDAndCreatedDate(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        let id = try await sut.insert(item: uniqueVaultItem().makeWritable())
        let before = try #require(try await sut.allVaultItems().first)

        try await sut.update(id: id, item: uniqueVaultItem(userDescription: "Updated").makeWritable())

        let after = try #require(try await sut.allVaultItems().first)
        #expect(after.id == id)
        #expect(after.metadata.created == before.metadata.created)
        #expect(after.metadata.updated >= before.metadata.updated)
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func updateByID_removesTagsTheWriteNoLongerHas(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        let tagA = try await sut.insertTag(item: anyVaultItemTag(name: "A").makeWritable())
        let tagB = try await sut.insertTag(item: anyVaultItemTag(name: "B").makeWritable())
        let id = try await sut.insert(item: uniqueVaultItem(tags: [tagA, tagB]).makeWritable())

        try await sut.update(id: id, item: uniqueVaultItem(tags: [tagA]).makeWritable())

        let items = try await sut.retrieve(query: .init()).items
        #expect(items.map(\.metadata.tags) == [[tagA]])
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func updateByID_canChangeTheKindOfItem(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        let note = VaultItem.Payload.secureNote(anySecureNote(title: "Note", contents: "Contents"))
        let id = try await sut.insert(item: uniqueVaultItem(item: note).makeWritable())
        let code = VaultItem.Payload.otpCode(anyOTPAuthCode(issuerName: "Issuer"))

        try await sut.update(id: id, item: uniqueVaultItem(item: code).makeWritable())

        let items = try await sut.allVaultItems()
        #expect(items.map(\.item) == [code])
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func reorder_emptyItemsHasNoEffectOnEmptyStore(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        try await sut.reorder(items: [], to: .start)
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func reorder_nonEmptyItemsHasNoEffectOnEmptyStore(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        try await sut.reorder(items: [.init(id: UUID())], to: .start)
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func reorder_reorderToAfterThrowsErrorIfItemDoesNotExist(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        let code = uniqueVaultItem().makeWritable()
        let id = try await sut.insert(item: code)

        await #expect(throws: (any Error).self) {
            try await sut.reorder(
                items: [id],
                to: .after(.init(id: UUID())),
            )
        }
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func reorder_reordersAllItemsIfMovingToStart(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func reorder_reordersAllIfMovingToAfterOtherItem(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func exportVault_hasNoSideEffectsOnEmptyVault(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        _ = try await sut.exportVault(userDescription: "")

        let result = try await sut.retrieve(query: .init())
        #expect(result == .empty())
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func exportVault_hasNoSideEffectsOnNonEmptyVault(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func exportVault_empty(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        let export = try await sut.exportVault(userDescription: "my description!")

        #expect(export.userDescription == "my description!")
        #expect(export.items == [])
        #expect(export.tags == [])
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func exportVault_withContent(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveTags_returnsNoTagsIfThereAreNone(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        let tags = try await sut.retrieveTags()

        #expect(tags == [])
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func retrieveTags_returnsMultipleTags(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func insertTag_deliversNoErrorOnEmptyStore(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        try await sut.insertTag(item: anyVaultItemTag().makeWritable())
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func insertTag_deliversNoErrorOnNonEmptyStore(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        try await sut.insertTag(item: anyVaultItemTag().makeWritable())
        try await sut.insertTag(item: anyVaultItemTag().makeWritable())
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func insertTag_doesNotOverrideExactSameEntryAsUsesNewIDToUnique(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        let code = anyVaultItemTag().makeWritable()

        try await sut.insertTag(item: code)
        try await sut.insertTag(item: code)

        let result = try await sut.retrieveTags()
        #expect(result.count == 2)
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func insertTag_returnsUniqueCodeIDAfterSuccessfulInsert(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        let code = anyVaultItemTag().makeWritable()

        var ids = [UUID]()
        for _ in 0 ..< 5 {
            let id = try await sut.insertTag(item: code)
            ids.append(id.id)
        }

        let result = try await sut.retrieveTags()
        #expect(result.map(\.id.id) == ids)
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func deleteTag_hasNoEffectOnEmptyStore(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        try await sut.deleteTag(id: .init(id: UUID()))

        let result = try await sut.retrieveTags()
        #expect(result == [])
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func deleteTag_deletesSingleEntryMatchingID(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        let code = anyVaultItemTag().makeWritable()

        let id = try await sut.insertTag(item: code)

        try await sut.deleteTag(id: id)

        let result = try await sut.retrieveTags()
        #expect(result == [])
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func deleteTag_hasNoEffectOnNoMatchingTag(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func deleteTag_removesFromModels(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func updateTag_deliversErrorIfCodeDoesNotAlreadyExist(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        await #expect(throws: (any Error).self) {
            try await sut.updateTag(id: .init(id: UUID()), item: anyVaultItemTag().makeWritable())
        }
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func updateTag_hasNoEffectOnEmptyStorageIfDoesNotAlreadyExist(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        await #expect(throws: (any Error).self) {
            try await sut.updateTag(id: .init(id: UUID()), item: anyVaultItemTag().makeWritable())
        }

        let result = try await sut.retrieveTags()
        #expect(result == [])
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func updateTag_hasNoEffectOnNonEmptyStorageIfDoesNotAlreadyExist(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func updateTag_updatesDataForValidTag(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        let initial = anyVaultItemTag().makeWritable()
        let id = try await sut.insertTag(item: initial)

        let newTag = anyVaultItemTag(name: "this is the new name").makeWritable()
        try await sut.updateTag(id: id, item: newTag)

        let result = try await sut.retrieveTags()
        #expect(result.map(\.name) == ["this is the new name"])
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func updateTag_hasNoSideEffectsOnOtherTags(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func updateTag_itemsCarryingTheTagKeepIt(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        let tagID = try await sut.insertTag(item: anyVaultItemTag(name: "Before").makeWritable())
        try await sut.insert(item: uniqueVaultItem(tags: [tagID]).makeWritable())

        try await sut.updateTag(id: tagID, item: anyVaultItemTag(name: "After").makeWritable())

        let items = try await sut.retrieve(query: .init()).items
        #expect(items.map(\.metadata.tags) == [[tagID]])
        #expect(try await sut.retrieveTags().map(\.name) == ["After"])
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func deleteVault_hasNoEffectOnEmptyStore(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        try await sut.deleteVault()

        try await sut.assertStoreEmpty()
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func deleteVault_removesAllItems(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

        try await sut.assertStoreEmpty()
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func incrementCounter_throwsForNonTOTP(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        let note = anySecureNote().wrapInAnyVaultItem().makeWritable()
        let id1 = try await sut.insert(item: note)

        await #expect(throws: (any Error).self) {
            try await sut.incrementCounter(id: id1)
        }
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func incrementCounter_incrementsHOTP(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

    @Test(arguments: VaultStoreEngine.allCases)
    func importAndMergeVault_importsEmptyToEmptyVault(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        let payload = VaultApplicationPayload(userDescription: "", items: [], tags: [])

        try await sut.importAndMergeVault(payload: payload)

        try await sut.assertStoreEmpty()
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func importAndMergeVault_emptyToNonEmptyVault(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

        try await sut.assertStoreContains(exactlyItems: items)
        try await sut.assertStoreContains(exactlyTags: tags)
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func importAndMergeVault_linksItemsToTagsImportedWithThem(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        let tag = anyVaultItemTag(name: "Imported")
        let item = uniqueVaultItem(tags: [tag.id])
        let payload = VaultApplicationPayload(userDescription: "", items: [item], tags: [tag])

        try await sut.importAndMergeVault(payload: payload)

        try await sut.assertStoreContains(exactlyItems: [item])
        try await sut.assertStoreContains(exactlyTags: [tag])
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func importAndMergeVault_newerItemReplacesItsTags(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        let tagA = anyVaultItemTag(name: "A")
        let tagB = anyVaultItemTag(name: "B")
        let older = uniqueVaultItem(updatedDate: Date(timeIntervalSince1970: 100), tags: [tagA.id, tagB.id])
        try await sut.importAndMergeVault(payload: .init(userDescription: "", items: [older], tags: [tagA, tagB]))

        let newer = uniqueVaultItem(id: older.id, updatedDate: Date(timeIntervalSince1970: 200), tags: [tagB.id])
        try await sut.importAndMergeVault(payload: .init(userDescription: "", items: [newer], tags: []))

        try await sut.assertStoreContains(exactlyItems: [newer])
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func importAndMergeVault_lastCopyOfAnItemInThePayloadWins(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        let tagA = anyVaultItemTag(name: "A")
        let tagB = anyVaultItemTag(name: "B")
        let first = uniqueVaultItem(updatedDate: Date(timeIntervalSince1970: 100), userDescription: "First", tags: [
            tagA.id,
        ])
        let second = uniqueVaultItem(
            id: first.id,
            updatedDate: Date(timeIntervalSince1970: 200),
            userDescription: "Second",
            tags: [tagB.id],
        )

        try await sut.importAndMergeVault(payload: .init(userDescription: "", items: [first, second], tags: [
            tagA,
            tagB,
        ]))

        try await sut.assertStoreContains(exactlyItems: [second])
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func importAndOverrideVault_dropsTagsThePayloadDoesNotHave(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        let oldTag = try await sut.insertTag(item: anyVaultItemTag(name: "Old").makeWritable())
        let id = try await sut.insert(item: uniqueVaultItem(tags: [oldTag]).makeWritable())
        let restored = uniqueVaultItem(id: id, tags: [oldTag])

        try await sut.importAndOverrideVault(payload: .init(userDescription: "", items: [restored], tags: []))

        let items = try await sut.allVaultItems()
        #expect(items.map(\.metadata.tags) == [[]])
        try await sut.assertStoreContains(exactlyTags: [])
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func importAndOverrideVault_linksItemsToTagsImportedWithThem(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        try await sut.insert(item: uniqueVaultItem().makeWritable())
        let tag = anyVaultItemTag(name: "Imported")
        let item = uniqueVaultItem(tags: [tag.id])
        let payload = VaultApplicationPayload(userDescription: "", items: [item], tags: [tag])

        try await sut.importAndOverrideVault(payload: payload)

        try await sut.assertStoreContains(exactlyItems: [item])
        try await sut.assertStoreContains(exactlyTags: [tag])
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func importAndMergeVault_importsNonEmptyToEmptyVault(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

        try await sut.assertStoreContains(exactlyItems: items)
        try await sut.assertStoreContains(exactlyTags: tags)
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func importAndMergeVault_importsNonEmptyToNonEmptyVault(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

        try await sut.assertStoreContains(exactlyItems: items1 + items2)
        try await sut.assertStoreContains(exactlyTags: tags1 + tags2)
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func importAndMergeVault_overridesItemWithSameIDAndLaterDate(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

        try await sut.assertStoreContains(exactlyItems: [item2, itemX])
        try await sut.assertStoreContains(exactlyTags: [tag2, tagX])
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func importAndMergeVault_retainsExistingItemWithLaterUpdatedDate(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

        try await sut.assertStoreContains(exactlyItems: [item1, itemX])
        // Tags are always updated: they have no date to compare.
        try await sut.assertStoreContains(exactlyTags: [tag2, tagX])
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func importAndOverrideVault_importsEmptyToEmptyVault(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        let payload = VaultApplicationPayload(userDescription: "", items: [], tags: [])

        try await sut.importAndOverrideVault(payload: payload)

        try await sut.assertStoreEmpty()
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func importAndOverrideVault_importsEmptyToNonEmptyVault(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

        try await sut.assertStoreEmpty()
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func importAndOverrideVault_importsNonEmptyToEmptyVault(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

        try await sut.assertStoreContains(exactlyItems: items)
        try await sut.assertStoreContains(exactlyTags: tags)
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func importAndOverrideVault_overridesExistingDataWithNew(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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

        try await sut.assertStoreContains(exactlyItems: items2)
        try await sut.assertStoreContains(exactlyTags: tags2)
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func deleteItemsMatchingKillphrase_hasNoEffectIfVaultEmpty(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
        let didDelete = await sut.deleteItems(matchingKillphrase: "a", using: testDigester)

        #expect(didDelete == false)
        try await sut.assertStoreContains(exactlyItems: [])
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func deleteItemsMatchingKillphrase_deletesSingleItem(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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
        try await sut.assertStoreContains(exactlyItems: [item2, item3])
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func deleteItemsMatchingKillphrase_deletesMultipleItems(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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
        try await sut.assertStoreContains(exactlyItems: [item3])
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func deleteItemsMatchingKillphrase_deletesExactMatchOnly(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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
        try await sut.assertStoreContains(exactlyItems: [item2, item3])
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func deleteItemsMatchingKillphrase_matchesQueryWithSurroundingWhitespace(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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
        try await sut.assertStoreContains(exactlyItems: [item2])
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func deleteItemsMatchingKillphrase_doesNotDeleteEmptyKillphraseItems(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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
        try await sut.assertStoreContains(exactlyItems: [item1, item3])
    }

    @Test(arguments: VaultStoreEngine.allCases)
    func deleteItemsMatchingKillphrase_doesNotDeleteAnyItemsIfPhraseIsBlank(engine: VaultStoreEngine) async throws {
        let sut = try await engine.makeStore()
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
        try await sut.assertStoreContains(exactlyItems: [item1, item2, item3])
    }
}
