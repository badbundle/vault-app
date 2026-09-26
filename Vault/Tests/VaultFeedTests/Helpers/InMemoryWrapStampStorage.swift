import Foundation
import FoundationExtensions
@testable import VaultFeed

/// Keeps the wrap stamp in memory, logging each save into a log it can share with other test doubles.
final class InMemoryWrapStampStorage: VaultWrapStampStorage {
    struct Failure: Error {}

    private let stamp = SharedMutex<UInt64?>(nil)
    private let failsToSave = SharedMutex(false)
    private let log: SharedMutex<[String]>?

    init(stamp: UInt64? = nil, log: SharedMutex<[String]>? = nil) {
        self.stamp.modify { $0 = stamp }
        self.log = log
    }

    /// The stamp saved, in milliseconds since 1970.
    var value: UInt64? {
        stamp.value
    }

    func failToSave() {
        failsToSave.modify { $0 = true }
    }

    func load() throws -> UInt64? {
        stamp.value
    }

    func save(_ newStamp: UInt64) throws {
        guard !failsToSave.value else { throw Failure() }
        stamp.modify { $0 = newStamp }
        log?.modify { $0.append("stamp the wrap") }
    }
}

extension VaultDeviceWrapStamper {
    /// A stamper that keeps its stamp in memory, telling the time with `currentDate`.
    static func inMemory(
        storage: InMemoryWrapStampStorage = InMemoryWrapStampStorage(),
        currentDate: @escaping @Sendable () -> Date = { Date() },
    ) -> VaultDeviceWrapStamper {
        VaultDeviceWrapStamper(storage: storage, currentDate: currentDate)
    }
}
