import Foundation

/// A shard/block of data from a larger group.
public struct DataShard: Equatable, Codable, Sendable {
    /// Information about the group that this data is part of.
    public var group: GroupInfo
    /// The partial data, which should be concatented with all the other blocks in order.
    public var data: Data

    enum CodingKeys: String, CodingKey {
        case group = "G"
        case data = "D"
    }
}

extension DataShard {
    public struct GroupInfo: Equatable, Hashable, Codable, Identifiable, Sendable {
        /// An ID shared by all of the `SplitDataBlock` instances in this series.
        ///
        /// This ensures we can detect if a block is not in the group.
        /// It doesn't need to be globally unique, just roughly unique to each individual user.
        public var id: UInt16
        /// The number that this block is in the group.
        public var number: Int
        /// The total number of blocks in the group.
        public var totalNumber: Int

        enum CodingKeys: String, CodingKey {
            case id = "ID"
            case number = "I"
            case totalNumber = "N"
        }
    }
}
