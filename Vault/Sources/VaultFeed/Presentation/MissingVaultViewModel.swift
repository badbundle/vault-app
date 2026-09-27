import Foundation

/// Erases and starts again with an empty vault, when the vault's data is missing and nothing shows an erase was meant
/// (`VaultStorageRecovery.Failure.vaultMissing`).
///
/// A restore or a move to another iPhone can bring back the storage state without the vault's file. Erasing then
/// deletes every keychain item, and the file too if it turns up later, so the app never does it by itself: the failure
/// screen offers it, and it runs only once the user has confirmed.
@MainActor
@Observable
public final class MissingVaultViewModel {
    public enum State: Equatable, Sendable {
        /// Nothing has been erased. The user can restore the vault, or choose to erase and start again.
        case waiting
        /// The erase is running.
        case erasing
        /// The erase stopped with an error. The user can try again, and the next launch finishes it too.
        case failed
        /// It's finished: the vault is a fresh, empty plain store.
        case erased
    }

    public private(set) var state = State.waiting

    private let erase: () async throws -> Void

    /// - Parameter erase: Erases every vault and starts the app on the fresh store it leaves. It's safe to repeat
    ///   until it succeeds.
    public init(erase: @escaping () async throws -> Void) {
        self.erase = erase
    }

    /// Erases and starts again. Call it only once the user has confirmed it.
    ///
    /// It does nothing while it's already running, or once the erase has finished: erasing again then would erase the
    /// fresh store.
    public func eraseAndStartAgain() async {
        guard state == .waiting || state == .failed else { return }
        state = .erasing
        do {
            try await erase()
            state = .erased
        } catch {
            state = .failed
        }
    }
}
