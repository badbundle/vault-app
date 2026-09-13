import Foundation

public enum TaskRaceError: Error, Equatable, Hashable {
    case noTasksScheduled
}

/// Operation that can yield a value or throw, to be used in `Task.race`.
public typealias TaskRace<T> = @Sendable () async throws -> T

extension Task where Failure == any Error {
    /// Race for the first result by any of the provided tasks.
    ///
    /// This will return the first valid result or throw the first thrown error by *any* child task.
    /// Cancelled tasks are ignored as they are no longer eligible to participate in the race.
    ///
    /// - throws: The first error yielded for any child tasks, or `CancellationError` if cancelled.
    /// - returns: The value for the first resolved result, throws if it's an error.
    public static func race(
        priority: TaskPriority? = nil,
        firstResolved tasks: [TaskRace<Success>],
    ) async throws -> Success {
        try await withThrowingTaskGroup(of: Success.self) { group -> Success in
            for task in tasks {
                group.addTask(priority: priority) {
                    try await task()
                }
            }
            defer { group.cancelAll() }
            try Task<Never, Never>.checkCancellation()

            while let nextResult = await group.nextResult() {
                try Task<Never, Never>.checkCancellation()
                switch nextResult {
                case let .failure(error) where error is CancellationError:
                    // Ignore cancelled tasks - they're no longer eligible
                    continue
                case let .failure(error):
                    throw error
                case let .success(value):
                    return value
                }
            }

            // All tasks were cancelled or no tasks scheduled
            throw TaskRaceError.noTasksScheduled
        }
    }

    /// Race for the first valid value.
    ///
    /// Ignores errors that may be thrown and waits for the first result.
    /// If all tasks fail, returns `nil`.
    ///
    /// - throws: `CancellationError` if cancelled.
    /// - returns: The first successful value yielded by any of the child tasks.
    public static func race(
        priority: TaskPriority? = nil,
        firstValue tasks: [TaskRace<Success>],
    ) async throws -> Success? {
        try await withThrowingTaskGroup(of: Success.self) { group -> Success? in
            try Task<Never, Never>.checkCancellation()
            if tasks.isEmpty {
                throw TaskRaceError.noTasksScheduled
            }
            for task in tasks {
                group.addTask(priority: priority) {
                    try await task()
                }
            }

            defer { group.cancelAll() }
            try Task<Never, Never>.checkCancellation()

            while let nextResult = await group.nextResult() {
                try Task<Never, Never>.checkCancellation()
                switch nextResult {
                case .failure:
                    continue
                case let .success(result):
                    return result
                }
            }

            // If all the racing tasks error, we will reach this point.
            return nil
        }
    }
}
