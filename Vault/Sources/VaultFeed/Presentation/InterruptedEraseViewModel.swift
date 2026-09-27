import Foundation

/// Finishes an erase the app was stopped in the middle of (`VaultEraser`), before the vault is shown.
///
/// Until it's done, nothing may read the vault, or load the keychain items the erase deletes, so the app shows this
/// instead of the vault. If the erase fails, the user can try again, and the next launch tries again too.
@MainActor
@Observable
public final class InterruptedEraseViewModel {
    public enum State: Equatable, Sendable {
        /// The erase is running, or about to.
        case erasing
        /// It stopped with an error. The vault can't be shown until it's finished.
        case failed
        /// It's finished: the vault is a fresh, empty plain store.
        case erased
    }

    public private(set) var state = State.erasing

    private let erase: () async throws -> Void
    private var isRunning = false

    /// - Parameter erase: Finishes the erase. It's safe to repeat until it succeeds.
    public init(erase: @escaping () async throws -> Void) {
        self.erase = erase
    }

    /// Finishes the erase, or tries again after it failed.
    ///
    /// It does nothing while it's already running, or once the erase has finished: erasing again then would erase the
    /// fresh store.
    public func finish() async {
        guard state != .erased, !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        state = .erasing
        do {
            try await erase()
            state = .erased
        } catch {
            state = .failed
        }
    }
}
