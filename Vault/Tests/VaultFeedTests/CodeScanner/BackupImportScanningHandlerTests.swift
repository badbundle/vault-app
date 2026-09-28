import Foundation
import Testing
import VaultBackup
@testable import VaultFeed

struct BackupImportScanningHandlerTests {
    let sut = BackupImportScanningHandler()

    @Test
    func hasPartialState_isInitiallyFalse() {
        #expect(sut.hasPartialState == false)
    }

    @Test
    func hasPartialState_isTrueAfterScan() {
        _ = sut.decode(data: """
        {
            "G":{"ID":10,"N":4,"I":0},
            "D": "AA=="
        }
        """)

        #expect(sut.hasPartialState == true)
    }

    @Test(arguments: ["", "invalid", "{}"])
    func decode_invalidDataReportsInvalidCode(string: String) {
        let result = sut.decode(data: string)
        #expect(result == .continueScanning(.invalidCode))
    }

    @Test
    func makeSimulatedHandler_returnsExampleVault() {
        let simulated = sut.makeSimulatedHandler()

        let result = simulated.decodeSimulated()

        guard case let .endScanning(.dataRetrieved(vault)) = result else {
            Issue.record("Expected simulated vault")
            return
        }
        #expect(vault.version == "1.0.0")
        #expect(vault.data.isEmpty == false)
    }

    @Test(arguments: ["", "invalid", "{}"])
    func decode_addShardErrorIgnoresError(string _: String) throws {
        let result1 = sut.decode(data: """
        {
            "G":{"ID":10,"N":4,"I":0},
            "D": "AA=="
        }
        """)
        try #require(result1 == .continueScanning(.success))

        let result2 = sut.decode(data: """
        {
            "G":{"ID":11,"N":4,"I":0},
            "D": "AA=="
        }
        """)
        #expect(result2 == .continueScanning(.ignore), "Different group number is an ignorable error")
    }

    @Test(arguments: [
        #"{"G":{"ID":10,"N":0,"I":0},"D":"AA=="}"#,
        #"{"G":{"ID":10,"N":-4,"I":0},"D":"AA=="}"#,
        #"{"G":{"ID":10,"N":9223372036854775807,"I":0},"D":"AA=="}"#,
        #"{"G":{"ID":10,"N":4,"I":4},"D":"AA=="}"#,
        #"{"G":{"ID":10,"N":4,"I":-1},"D":"AA=="}"#,
    ])
    func decode_outOfRangeGroupReportsInvalidCodeAndKeepsScanning(string: String) throws {
        let first = sut.decode(data: #"{"G":{"ID":10,"N":2,"I":0},"D":"AA=="}"#)
        try #require(first == .continueScanning(.success))

        let rejected = sut.decode(data: string)

        #expect(rejected == .continueScanning(.invalidCode))
        #expect(sut.shardState?.totalNumberOfShards == 2)
        #expect(sut.shardState?.collectedShardIndexes == [0])
        let last = sut.decode(data: #"{"G":{"ID":10,"N":2,"I":1},"D":"AA=="}"#)
        #expect(last == .endScanning(.unrecoverableError), "The group completes, but AA== twice isn't a valid vault.")
    }

    @Test
    func decode_outOfRangeGroupAsTheFirstCodeLeavesNoState() {
        let result = sut.decode(data: #"{"G":{"ID":10,"N":-4,"I":0},"D":"AA=="}"#)

        #expect(result == .continueScanning(.invalidCode))
        #expect(sut.hasPartialState == false)
    }

    @Test(arguments: [0, 1, 2, 3])
    func decode_partialShardContinuesScanning(shardNumber: Int) {
        let result = sut.decode(data: """
        {
            "G":{"ID":10,"N":4,"I":\(shardNumber)},
            "D": "AA=="
        }
        """)
        #expect(result == .continueScanning(.success))
    }

    @Test
    func decode_fullShardSequenceCompletes() throws {
        let expectedVault = EncryptedVault(
            version: "1.0.0",
            data: Data(repeating: 0x34, count: 1000),
            authentication: Data(),
            encryptionIV: Data(repeating: 0x46, count: 500),
            keygenSalt: Data(repeating: 0x21, count: 100),
            keygenSignature: "34",
        )
        let expectedVaultData = try EncryptedVaultCoder().encode(vault: expectedVault)
        let builder = DataShardBuilder()
        let shards = builder.makeShards(from: expectedVaultData)
        let encodedShards = try shards.map {
            try EncryptedVaultCoder().encode(shard: $0)
        }
        #expect(sut.hasPartialState == false)

        // Intermediate shards should continue scanning.
        for encodedShard in encodedShards[0 ..< encodedShards.count - 1] {
            let string = try #require(String(data: encodedShard, encoding: .utf8))
            let result = sut.decode(data: string)
            try #require(result == .continueScanning(.success))
            #expect(sut.hasPartialState == true)
        }

        // The last shard triggers the completion.
        let lastShard = try #require(encodedShards.last)
        let string = try #require(String(data: lastShard, encoding: .utf8))
        let result = sut.decode(data: string)
        #expect(result == .endScanning(.dataRetrieved(expectedVault)))
        #expect(sut.hasPartialState == true)
    }

    @Test
    func decodeInvalidFullDataEndsWithUnrecoverableError() throws {
        let result1 = sut.decode(data: """
        {
            "G":{"ID":10,"N":2,"I":0},
            "D": "AA=="
        }
        """)
        try #require(result1 == .continueScanning(.success))

        let result2 = sut.decode(data: """
        {
            "G":{"ID":10,"N":2,"I":1},
            "D": "AA=="
        }
        """)
        #expect(result2 == .endScanning(.unrecoverableError), "Because AA== twice is not a valid vault.")
    }
}
