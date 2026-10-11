import Foundation

extension Task where Failure == any Error {
    /// Runs some work on a new background task, nonisolated from the current parent task.
    ///
    /// This is useful for heavy background work that is triggered from a higher priority task/actor.
    /// For example, starting some long-running work from the `MainActor` that we don't want to block the `MainActor`.
    ///
    /// If the parent task is cancelled, this will propagate to this task as well, throwing `CancellationError` at the
    /// body's discretion.
    public static func background(body: @Sendable @escaping () async throws(Failure) -> Success) async throws(Failure)
        -> Success
    {
        try await runDetached(priority: .background, body: body)
    }

    /// Runs some work the user is waiting on, such as deriving a key from a password they've just entered, on a new
    /// task at user-initiated priority, nonisolated from the current parent task. Cancelling works as for
    /// `background(body:)`.
    ///
    /// At background priority, an iPhone can keep the work, and any threads it starts, to its efficiency cores, which
    /// can make a derivation of seconds take minutes.
    public static func userInitiated(body: @Sendable @escaping () async throws(Failure) -> Success)
        async throws(Failure) -> Success
    {
        try await runDetached(priority: .userInitiated, body: body)
    }

    /// Runs some work on a new task at `priority`, nonisolated from the current parent task, and waits for it.
    ///
    /// If the parent task is cancelled, this will propagate to this task as well, throwing `CancellationError` at the
    /// body's discretion.
    public static func runDetached(
        priority: TaskPriority,
        body: @Sendable @escaping () async throws(Failure) -> Success,
    ) async throws(Failure) -> Success {
        let runningTask = SharedMutex<Task<Success, Failure>?>(nil)
        return try await withTaskCancellationHandler {
            let task = Task.detached(priority: priority) {
                try await body()
            }
            runningTask.modify { $0 = task }
            try Task<Never, Never>.checkCancellation()
            return try await task.value
        } onCancel: {
            runningTask.modify { $0?.cancel() }
        }
    }
}
