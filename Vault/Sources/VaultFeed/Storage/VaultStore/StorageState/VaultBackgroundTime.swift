import Foundation

/// Asks the system for time to finish a change of storage mode, so the app isn't suspended in the middle of one.
///
/// iOS terminates an app that's suspended while it holds a file lock in the App Group's container (`0xdead10cc`), and
/// `vault-slots.lock` is one. Converting the plain store (`VaultEncryptionConverter`) and rekeying the vault
/// (`VaultPasswordChangeService`) hold it for seconds, so the app asks for background time around them. In the app,
/// that's `VaultBackgroundTime.application`, from VaultiOS. If the time runs out anyway and the app is terminated,
/// launch recovery finishes or undoes the change from its journal, as after any other crash.
public struct VaultBackgroundTime: Sendable {
    private let begin: @Sendable () async -> @Sendable () async -> Void

    /// - Parameter begin: Asks for the time, and returns what gives it back. The system can take the time back
    ///   early; then what `begin` returns should do nothing.
    public init(begin: @escaping @Sendable () async -> @Sendable () async -> Void) {
        self.begin = begin
    }

    /// Asks for no time: for tests, and for code that isn't running in an app.
    public static let none = VaultBackgroundTime { {} }

    /// Runs `body` with the time asked for, and gives it back once `body` has finished, however it finishes.
    func whileRunning<T: Sendable>(
        isolation _: isolated (any Actor)? = #isolation,
        _ body: () async throws -> T,
    ) async throws -> T {
        let end = await begin()
        do {
            let result = try await body()
            await end()
            return result
        } catch {
            await end()
            throw error
        }
    }
}
