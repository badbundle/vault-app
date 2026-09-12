import Foundation
import FoundationExtensions
import TestHelpers
import Testing

/// A common pattern we use in these tests is starting a background task that calls `wait`.
/// We then want to check the state of the `sut` while it is waiting in the background.
///
/// To maximise correctness, there's a few things to keep in mind:
///  - The task should be `detached` to ensure that this task is running independently of the test task.
///  - After `await`ing the start of the task, call `Task.yield()` to ensure that the SUT is actually waiting.
///  - The priority of this `detached` task should be `high` to make sure that yielding doesn't just resume on the
///  test task immediately.
struct PendingValueTests {
    enum TestError: Error {
        case testCase
        case testCase2
    }

    private typealias SUT = Pending<Int>
    private let sut = SUT()

    @Test
    func wait_throwsCancellationErrorIfCancelled() async throws {
        try await confirmation { confirmation in
            let startedWaiting = Pending.signal()
            let finishedWaiting = Pending.signal()
            let task = Task.detached(priority: .high) {
                await startedWaiting.fulfill()
                do {
                    _ = try await sut.wait()
                } catch is CancellationError {
                    confirmation.confirm()
                }
                await finishedWaiting.fulfill()
            }

            try await startedWaiting.wait()
            await Task.yield()

            task.cancel()

            try await finishedWaiting.wait()
        }
    }

    @Test
    func wait_asyncFulfillsWithDifferingValuesWhenCalledMoreThanOnce() async throws {
        let result1 = try await awaitValueInBackground(on: sut) {
            await sut.fulfill(100)
        }
        #expect(result1.withAnyEquatableError() == .success(100))

        let result2 = try await awaitValueInBackground(on: sut) {
            await sut.fulfill(101)
        }
        #expect(result2.withAnyEquatableError() == .success(101))
    }

    @Test
    func wait_asyncDoesNotFulfillMoreThanOnceForSingleValue() async throws {
        let result1 = try await awaitValueInBackground(on: sut) {
            await sut.fulfill(100)
        }
        #expect(result1.withAnyEquatableError() == .success(100))

        await awaitNoValueProduced(on: sut)

        await sut.cancel()
    }

    @Test
    func wait_throwsAlreadyWaitingErrorIfAlreadyWaiting() async {
        var task: Task<Void, any Error>?
        await withCheckedContinuation { continutation in
            task = Task.detached(priority: .high) {
                continutation.resume()
                _ = try await sut.wait()
            }
        }
        await Task.yield()

        await #expect(throws: SUT.Error.alreadyWaiting, performing: {
            _ = try await sut.wait()
        })

        task?.cancel()
        await sut.cancel()
    }

    @Test
    func wait_timeoutFulfillsWithError() async {
        await #expect(throws: TimeoutError.self, performing: {
            _ = try await sut.wait(timeout: .nanoseconds(1))
        })

        await sut.cancel()
    }

    @Test
    func fulfill_unsuspendsAwait() async throws {
        let result = try await awaitValueInBackground(on: sut) {
            await sut.fulfill(42)
        }

        #expect(result.withAnyEquatableError() == .success(42))
    }

    @Test
    func fulfill_beforeAwaitingReturnsInitialValue() async throws {
        await sut.fulfill(42)

        let value = try await sut.wait()

        #expect(value == 42)
    }

    @Test
    func fulfill_remembersMostRecentValueOnly() async throws {
        await sut.fulfill(42)
        await sut.fulfill(43)
        await sut.fulfill(44)

        let value = try await sut.wait()
        #expect(value == 44)
    }

    @Test
    func reject_unsuspendsAwait() async throws {
        let result = try await awaitValueInBackground(on: sut) {
            await sut.reject(error: TestError.testCase)
        }

        #expect(throws: TestError.testCase, performing: {
            try result.get()
        })
    }

    @Test
    func reject_beforeAwaitResolvesWithInitialError() async {
        await sut.reject(error: TestError.testCase)

        await #expect(throws: TestError.testCase, performing: {
            _ = try await sut.wait()
        })
    }

    @Test
    func reject_resolvesWithMostRecentError() async {
        await sut.reject(error: TestError.testCase)
        await sut.reject(error: TestError.testCase2)

        await #expect(throws: TestError.testCase2, performing: {
            _ = try await sut.wait()
        })
    }

    @Test
    func isWaiting_initiallyFalse() async {
        let isWaiting = await sut.isWaiting
        #expect(!isWaiting)
    }

    @Test
    func isWaiting_trueWhenWaiting() async throws {
        let waitForTaskStart = Pending.signal()
        Task.detached(priority: .high) {
            await waitForTaskStart.fulfill()
            // The wait is torn down by `sut.cancel()` at the end of the test, so a throw is expected.
            _ = try? await sut.wait()
        }

        try await waitForTaskStart.wait()
        await Task.yield()

        let isWaiting = await sut.isWaiting
        #expect(isWaiting)

        await sut.cancel()
    }

    @Test
    func isWaiting_falseWhenFulfilled() async throws {
        _ = try await awaitValueInBackground(on: sut) {
            await sut.fulfill(42)
        }

        let isWaiting = await sut.isWaiting
        #expect(!isWaiting)
    }

    @Test
    func isWaiting_falseWhenRejected() async throws {
        _ = try await awaitValueInBackground(on: sut) {
            await sut.reject(error: TestError.testCase)
        }

        let isWaiting = await sut.isWaiting
        #expect(!isWaiting)
    }

    @Test
    func isWaiting_falseWhenCancelled() async throws {
        _ = try await awaitValueInBackground(on: sut) {
            await sut.cancel()
        }

        let isWaiting = await sut.isWaiting
        #expect(!isWaiting)
    }
}

// MARK: Helpers

extension PendingValueTests {
    /// Forces the SUT to start awaiting before calling `action`.
    ///
    /// This ensures the last value cache is checked before any action (fulfill/reject) is called.
    /// Without this, you might acidentally call `fulfill`/`reject` before await, and thus the value will be cached.
    private func awaitValueInBackground(
        on sut: SUT,
        action: @Sendable () async -> Void,
    ) async throws -> Result<Int, any Error> {
        let startedWaiting = Pending.signal()
        let finishedWaiting = Pending.signal()

        let task = Task.detached(priority: .high) {
            await startedWaiting.fulfill()
            let result: Result<Int, any Error>
            do {
                let value = try await sut.wait()
                result = .success(value)
            } catch {
                result = .failure(error)
            }
            await finishedWaiting.fulfill()
            return result
        }

        try await startedWaiting.wait(timeout: .seconds(1))
        await Task.yield()

        await action()

        try await finishedWaiting.wait(timeout: .seconds(1))

        defer { task.cancel() }
        return await task.value
    }

    private func awaitNoValueProduced(on sut: SUT) async {
        // If no value is produced, this will timeout.
        await #expect(throws: TimeoutError.self, performing: {
            try await sut.wait(timeout: .seconds(1))
        })
    }
}

extension Result {
    struct AnyEquatableError: Error, Equatable {}
    func withAnyEquatableError() -> Result<Success, AnyEquatableError> {
        mapError { _ in AnyEquatableError() }
    }
}
