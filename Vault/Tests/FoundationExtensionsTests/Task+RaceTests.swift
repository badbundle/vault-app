import Foundation
import FoundationExtensions
import TestHelpers
import Testing

enum TaskRaceTests {
    struct FirstResolved {
        @Test
        func noScheduledTasksThrows() async throws {
            await #expect(throws: TaskRaceError.noTasksScheduled) {
                try await Task.race(firstResolved: [TaskRace<Void>]())
            }
        }

        @Test("Cancellation is always checked before returning")
        func noScheduledTasksCancelledThrowsCancellation() async throws {
            let cancellationWaiter = TaskCancellationWaiter()
            let parent = Task {
                // Only race once cancelled, as the task might otherwise run to completion before `cancel()`.
                await cancellationWaiter.waitForTaskCancellation()
                return try await Task.race(firstResolved: [TaskRace<Void>]())
            }
            parent.cancel()

            await #expect(throws: CancellationError.self) {
                try await parent.value
            }
        }

        @Test
        func propagatesCancellation() async throws {
            let parent = Task {
                try await Task.race(firstResolved: [longTask()])
            }
            parent.cancel()

            await #expect(throws: CancellationError.self) {
                _ = try await parent.value
            }
        }

        @Test(arguments: [TestTask.t1, .t2, .t3])
        func firstResolvedReturnsFirstResolvedValue(resolvingTask: TestTask) async throws {
            let pending1 = Pending.signal()
            let pending2 = Pending.signal()
            let pending3 = Pending.signal()
            let t1: TaskRace<Int> = {
                try await pending1.wait()
                return TestTask.t1.testValue
            }
            let t2: TaskRace<Int> = {
                try await pending2.wait()
                return TestTask.t2.testValue
            }
            let t3: TaskRace<Int> = {
                try await pending3.wait()
                return TestTask.t3.testValue
            }
            let parent = Task {
                try await Task.race(firstResolved: [t1, t2, t3])
            }
            switch resolvingTask {
            case .t1: await pending1.fulfill()
            case .t2: await pending2.fulfill()
            case .t3: await pending3.fulfill()
            }
            let value = try await parent.value

            #expect(value == resolvingTask.testValue)
        }

        @Test(arguments: [TestTask.t1, .t2, .t3])
        func errorInAnyTaskPropagatesError(erroringTask: TestTask) async {
            let pending1 = Pending.signal()
            let pending2 = Pending.signal()
            let pending3 = Pending.signal()
            let t1: TaskRace<Void> = {
                try await pending1.wait()
                if erroringTask == .t1 {
                    throw SomeError()
                }
            }
            let t2: TaskRace<Void> = {
                try await pending2.wait()
                if erroringTask == .t2 {
                    throw SomeError()
                }
            }
            let t3: TaskRace<Void> = {
                try await pending3.wait()
                if erroringTask == .t3 {
                    throw SomeError()
                }
            }
            let parent = Task {
                try await Task.race(firstResolved: [t1, t2, t3])
            }
            switch erroringTask {
            case .t1: await pending1.fulfill()
            case .t2: await pending2.fulfill()
            case .t3: await pending3.fulfill()
            }
            await #expect(throws: SomeError.self, performing: {
                _ = try await parent.value
            })
        }

        @Test
        func cancelledTasksAreIgnoredFromRace() async throws {
            let pending1 = Pending.signal()
            let pending2 = Pending.signal()
            let pending3 = Pending.signal()
            let t1: TaskRace<Int> = {
                try await pending1.wait()
                throw CancellationError()
            }
            let t2: TaskRace<Int> = {
                try await pending2.wait()
                return TestTask.t2.testValue
            }
            let t3: TaskRace<Int> = {
                try await pending3.wait()
                return TestTask.t3.testValue
            }
            let parent = Task {
                try await Task.race(firstResolved: [t1, t2, t3])
            }
            // Task 1 throws CancellationError first
            await pending1.fulfill()
            // Task 2 completes successfully
            await pending2.fulfill()
            // Race should ignore the cancelled task and return t2's value
            let value = try await parent.value

            #expect(value == TestTask.t2.testValue)
        }
    }

    struct FirstValue {
        @Test
        func noScheduledTasksThrows() async throws {
            await #expect(throws: TaskRaceError.noTasksScheduled) {
                try await Task.race(firstValue: [TaskRace<Void>]())
            }
        }

        @Test("Cancellation is always checked before returning")
        func noScheduledTasksCancelledThrowsCancellation() async throws {
            let cancellationWaiter = TaskCancellationWaiter()
            let parent = Task {
                // Only race once cancelled, as the task might otherwise run to completion before `cancel()`.
                await cancellationWaiter.waitForTaskCancellation()
                return try await Task.race(firstValue: [TaskRace<Void>]())
            }
            parent.cancel()

            await #expect(throws: CancellationError.self) {
                try await parent.value
            }
        }

        @Test
        func propagatesCancellation() async throws {
            let parent = Task {
                try await Task.race(firstValue: [longTask()])
            }
            parent.cancel()

            await #expect(throws: CancellationError.self) {
                _ = try await parent.value
            }
        }

        @Test(arguments: [TestTask.t1, .t2, .t3])
        func firstResolvedReturnsFirstResolvedValue(resolvingTask: TestTask) async throws {
            let pending1 = Pending.signal()
            let pending2 = Pending.signal()
            let pending3 = Pending.signal()
            let t1: TaskRace<Int> = {
                try await pending1.wait()
                return TestTask.t1.testValue
            }
            let t2: TaskRace<Int> = {
                try await pending2.wait()
                return TestTask.t2.testValue
            }
            let t3: TaskRace<Int> = {
                try await pending3.wait()
                return TestTask.t3.testValue
            }
            let parent = Task {
                try await Task.race(firstValue: [t1, t2, t3])
            }

            switch resolvingTask {
            case .t1: await pending1.fulfill()
            case .t2: await pending2.fulfill()
            case .t3: await pending3.fulfill()
            }
            let value = try await parent.value

            #expect(value == resolvingTask.testValue)
        }

        @Test
        func ignoresErrorsUntilValue() async throws {
            let pending1 = Pending.signal()
            let pending2 = Pending.signal()
            let pending3 = Pending.signal()
            let t1: TaskRace<Int> = {
                try await pending1.wait()
                throw SomeError()
            }
            let t2: TaskRace<Int> = {
                try await pending2.wait()
                throw SomeError()
            }
            let t3: TaskRace<Int> = {
                try await pending3.wait()
                return 103
            }
            let parent = Task {
                try await Task.race(firstValue: [t1, t2, t3])
            }
            await pending1.fulfill()
            await pending2.fulfill()
            await pending3.fulfill()
            let value = try await parent.value

            #expect(value == 103)
        }

        @Test
        func allErroringTasksReturnsNil() async throws {
            let pending1 = Pending.signal()
            let pending2 = Pending.signal()
            let pending3 = Pending.signal()
            let t1: TaskRace<Int> = {
                try await pending1.wait()
                throw SomeError()
            }
            let t2: TaskRace<Int> = {
                try await pending2.wait()
                throw SomeError()
            }
            let t3: TaskRace<Int> = {
                try await pending3.wait()
                throw SomeError()
            }
            let parent = Task {
                try await Task.race(firstValue: [t1, t2, t3])
            }
            await pending1.fulfill()
            await pending2.fulfill()
            await pending3.fulfill()
            let value = try await parent.value

            #expect(value == nil)
        }
    }
}

private func longTask() -> TaskRace<Void> {
    {
        try await suspendForever()
    }
}

private struct SomeError: Error {}

enum TestTask: Equatable {
    case t1, t2, t3

    var testValue: Int {
        switch self {
        case .t1: 101
        case .t2: 102
        case .t3: 103
        }
    }
}
