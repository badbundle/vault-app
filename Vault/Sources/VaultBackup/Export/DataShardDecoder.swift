import Foundation

/// A shard decoding accumulator.
public struct DataShardDecoder {
    private var currentShards: [Int: DataShard] = [:]
    public private(set) var state: State?
    public var isReadyToDecode: Bool {
        state?.remainingIndexes.isEmpty == true
    }

    public struct State {
        var groupID: UInt16
        /// The remaining shared indexes in the group that need to be added.
        public var remainingIndexes: Set<Int>
        /// The indexes of the shards that we have scanned so far.
        public var collectedIndexes: Set<Int>
        /// The total number of shards in the group.
        public var total: Int
    }

    public enum AddShardError: Error, Equatable {
        case inconsistentGroup
        case shardAlreadyExists
        /// The shard's total is below 1 or above `maximumShardCount`.
        case totalOutOfRange
        /// The shard's number isn't within its own total.
        case numberOutOfRange

        /// Is this a non-critical error that can be resolved by scanning another code?
        public var canIgnoreError: Bool {
            switch self {
            case .inconsistentGroup, .shardAlreadyExists: true
            case .totalOutOfRange, .numberOutOfRange: false
            }
        }
    }

    /// The most shards a group can have.
    ///
    /// Each shard carries 500 bytes, so this allows a backup of about 32 MB, over a thousand times a typical one.
    /// A shard claiming a larger group is refused before anything is sized from it.
    public static let maximumShardCount = 1 << 16

    public enum DecoderError: Error, Equatable {
        case missingShards
    }

    public init() {}

    /// Adds another shard to the decoder.
    ///
    /// Use `decodeData` when ready to extract all the shards.
    /// A shard that's rejected leaves the decoder as it was.
    public mutating func add(shardData: Data) throws {
        let nextShard = try EncryptedVaultCoder().decode(dataShard: shardData)
        let group = nextShard.group
        try verifyShardGroupInfoIsValid(group)
        try verifyShardGroupIsConsistent(shard: nextShard)
        try verifyShardDoesNotExist(shard: nextShard)
        currentShards[group.number] = nextShard

        var nextState = state ?? State(
            groupID: group.id,
            remainingIndexes: Set(0 ..< group.totalNumber),
            collectedIndexes: [],
            total: group.totalNumber,
        )
        nextState.remainingIndexes.remove(group.number)
        nextState.collectedIndexes.insert(group.number)
        state = nextState
    }

    /// Extract the data based on the shards.
    public func decodeData() throws(DecoderError) -> Data {
        guard isReadyToDecode else { throw DecoderError.missingShards }
        let sortedShards = currentShards.sorted { $0.key < $1.key }.map(\.value)
        return sortedShards.reduce(into: Data()) { result, shard in
            result.append(shard.data)
        }
    }
}

// MARK: - Helpers

extension DataShardDecoder {
    /// Checks that the shard is not already in the decoder.
    private func verifyShardDoesNotExist(shard: DataShard) throws(AddShardError) {
        if currentShards[shard.group.number] != nil {
            throw AddShardError.shardAlreadyExists
        }
    }

    /// Checks the shard's own group details, before anything uses them.
    private func verifyShardGroupInfoIsValid(_ group: DataShard.GroupInfo) throws(AddShardError) {
        guard (1 ... Self.maximumShardCount).contains(group.totalNumber) else {
            throw AddShardError.totalOutOfRange
        }
        guard (0 ..< group.totalNumber).contains(group.number) else {
            throw AddShardError.numberOutOfRange
        }
    }

    /// Checks that the import is using the same group ID and total for all shards.
    /// If it isn't, then the shards do not compose a valid group.
    private func verifyShardGroupIsConsistent(shard: DataShard) throws(AddShardError) {
        guard let state else { return }
        if state.groupID != shard.group.id || state.total != shard.group.totalNumber {
            throw AddShardError.inconsistentGroup
        }
    }
}
