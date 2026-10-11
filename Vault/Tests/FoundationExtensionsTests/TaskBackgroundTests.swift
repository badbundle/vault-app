import Foundation
import FoundationExtensions
import TestHelpers
import Testing

@Suite("Task Background Tests", .timeLimit(.minutes(1)))
struct TaskBackgroundTests {
    @Test
    func runsTaskToCompletion() async throws {
        try await confirmation(expectedCount: 1) { confirmation in
            try await Task.background {
                confirmation.confirm()
            }
        }
    }

    @Test
    func rethrowsCancellation() async throws {
        let pending1 = Pending.signal()
        let outer = Task.detached {
            try await Task.background {
                await pending1.fulfill()
                try await suspendForever()
            }
            Issue.record("Should not reach here: Task.background should throw CancellationError")
        }

        try await pending1.wait() // wait for task to start

        outer.cancel()

        await #expect(throws: CancellationError.self) {
            try await outer.result.get()
        }
    }
}

@Suite(.timeLimit(.minutes(1)))
struct TaskUserInitiatedTests {
    @Test
    func runsAtUserInitiatedPriority() async throws {
        let (priority, qos) = try await Task.userInitiated {
            (Task.currentPriority, qos_class_self())
        }

        #expect(priority == .userInitiated)
        #expect(qos == QOS_CLASS_USER_INITIATED)
    }

    @Test
    func rethrowsCancellation() async throws {
        let started = Pending.signal()
        let outer = Task.detached {
            try await Task.userInitiated {
                await started.fulfill()
                try await suspendForever()
            }
            Issue.record("Should not reach here: Task.userInitiated should throw CancellationError")
        }
        try await started.wait()

        outer.cancel()

        await #expect(throws: CancellationError.self) {
            try await outer.result.get()
        }
    }

    /// The thread's own quality of service, which is what the threads a body starts take on. Awaiting the work from a
    /// task of higher priority can raise how it's scheduled for a while, but not this.
    @Test(arguments: [
        (TaskPriority.background, QOS_CLASS_BACKGROUND),
        (.utility, QOS_CLASS_UTILITY),
        (.userInitiated, QOS_CLASS_USER_INITIATED),
    ])
    func runDetached_runsOnAThreadOfThePriorityGiven(priority: TaskPriority, qos: qos_class_t) async throws {
        let ran = try await Task.runDetached(priority: priority) { qos_class_self() }

        #expect(ran == qos)
    }

    @Test
    func background_runsOnABackgroundThread() async throws {
        let ran = try await Task.background { qos_class_self() }

        #expect(ran == QOS_CLASS_BACKGROUND)
    }
}
