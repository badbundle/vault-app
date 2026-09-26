import Foundation
import FoundationExtensions
import Testing
@testable import VaultFeed

/// Wrap times only ever go forward on the device, whatever its clock says.
struct VaultDeviceWrapStamperTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let longAgo = Date(timeIntervalSince1970: 0)

    @Test
    func nextWrapStamp_withoutAStamp_isNow() throws {
        let storage = InMemoryWrapStampStorage()
        let sut = VaultDeviceWrapStamper.inMemory(storage: storage) { [now] in now }

        let stamp = try sut.nextWrapStamp(rewrapping: .distantPast)

        #expect(stamp == now)
        #expect(storage.value == 1_790_000_000_000)
    }

    @Test
    func nextWrapStamp_withTheClockAfterTheStampAndThePreviousWrap_isNow() throws {
        let storage = InMemoryWrapStampStorage(stamp: 1_700_000_000_000)
        let sut = VaultDeviceWrapStamper.inMemory(storage: storage) { [now] in now }

        #expect(try sut.nextWrapStamp(rewrapping: Date(timeIntervalSince1970: 1_600_000_000)) == now)
    }

    /// Setting the clock back doesn't make a wrap older than the last one this device made.
    @Test
    func nextWrapStamp_withTheClockSetBack_isAMillisecondAfterTheLastStamp() throws {
        let storage = InMemoryWrapStampStorage(stamp: 1_790_000_000_000)
        let sut = VaultDeviceWrapStamper.inMemory(storage: storage) { [longAgo] in longAgo }

        let first = try sut.nextWrapStamp(rewrapping: .distantPast)
        let second = try sut.nextWrapStamp(rewrapping: .distantPast)

        #expect(first == Date(timeIntervalSince1970: 1_790_000_000.001))
        #expect(second == Date(timeIntervalSince1970: 1_790_000_000.002))
        #expect(storage.value == 1_790_000_000_002)
    }

    /// Nor older than the previous wrap, even without a stamp.
    @Test
    func nextWrapStamp_rewrappingALaterWrap_isAMillisecondAfterIt() throws {
        let sut = VaultDeviceWrapStamper.inMemory { [longAgo] in longAgo }

        let stamp = try sut.nextWrapStamp(rewrapping: now)

        #expect(stamp == Date(timeIntervalSince1970: 1_790_000_000.001))
    }

    /// A stamp that isn't saved could be handed out again, so nothing is wrapped with it.
    @Test
    func nextWrapStamp_thatCannotBeSaved_throws() {
        let storage = InMemoryWrapStampStorage()
        storage.failToSave()
        let sut = VaultDeviceWrapStamper.inMemory(storage: storage) { [now] in now }

        #expect(throws: InMemoryWrapStampStorage.Failure.self) {
            try sut.nextWrapStamp(rewrapping: .distantPast)
        }
    }

    /// Two wraps at once never get the same stamp.
    @Test
    func nextWrapStamp_fromManyThreadsAtOnce_neverRepeats() async throws {
        let sut = VaultDeviceWrapStamper.inMemory { [longAgo] in longAgo }

        let stamps = try await withThrowingTaskGroup(of: Date.self) { group in
            for _ in 0 ..< 100 {
                group.addTask { try sut.nextWrapStamp(rewrapping: .distantPast) }
            }
            return try await group.reduce(into: [Date]()) { $0.append($1) }
        }

        #expect(Set(stamps).count == 100)
    }

    @Test
    func noteWrap_raisesTheStampToALaterWrap() throws {
        let storage = InMemoryWrapStampStorage(stamp: 1000)
        let sut = VaultDeviceWrapStamper.inMemory(storage: storage) { [longAgo] in longAgo }

        try sut.noteWrap(at: now)

        #expect(storage.value == 1_790_000_000_000)
        #expect(try sut.nextWrapStamp(rewrapping: .distantPast) == Date(timeIntervalSince1970: 1_790_000_000.001))
    }

    @Test
    func noteWrap_neverLowersTheStamp() throws {
        let storage = InMemoryWrapStampStorage(stamp: 1_790_000_000_000)
        let sut = VaultDeviceWrapStamper.inMemory(storage: storage) { [longAgo] in longAgo }

        try sut.noteWrap(at: Date(timeIntervalSince1970: 1000))

        #expect(storage.value == 1_790_000_000_000)
    }
}
