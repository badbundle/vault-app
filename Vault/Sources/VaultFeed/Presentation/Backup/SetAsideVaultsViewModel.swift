import Foundation
import FoundationExtensions

/// Tells the user about vaults set aside because they couldn't be opened, and deletes them when asked.
///
/// A set-aside vault is an unencrypted copy of the vault, and may hold the only copy of some items (see
/// `PersistedLocalVaultStoreArchives`). So it's never deleted automatically: only here, when the user asks and
/// has authenticated, or when they delete all data. Authentication guards against someone using an unattended
/// device, not against coercion (MANIFESTO C4).
@MainActor
@Observable
public final class SetAsideVaultsViewModel {
    /// The vaults set aside, oldest first.
    public private(set) var archives: [VaultStoreArchive] = []
    public private(set) var isDeleting = false
    public private(set) var deleteError: PresentationError?

    private let store: any VaultStoreArchiving
    private let authenticationService: DeviceAuthenticationService

    /// Loads what's set aside straight away, so the Backups page shows it from its first frame.
    public init(archives: any VaultStoreArchiving, authenticationService: DeviceAuthenticationService) {
        store = archives
        self.authenticationService = authenticationService
        reload()
    }

    /// What happened, in a sentence, or `nil` if nothing was set aside.
    public var summary: String? {
        guard let latest = archives.last else { return nil }
        let date = latest.date.formatted(date: .abbreviated, time: .omitted)
        return if archives.count == 1 {
            "Your vault couldn't be opened on \(date), so its files were set aside and a new vault was started."
        } else {
            "Your vault couldn't be opened \(archives.count) times, most recently on \(date). Each time, its files were set aside and a new vault was started."
        }
    }

    public func reload() {
        archives = store.archives()
    }

    /// Deletes every set-aside vault, once the user has authenticated.
    public func deleteAll() async {
        guard isDeleting == false, archives.isNotEmpty else { return }
        isDeleting = true
        defer { isDeleting = false }
        deleteError = nil

        do {
            try await authenticationService.validateAuthentication(reason: "Delete the set-aside vault")
        } catch {
            deleteError = PresentationError(
                userTitle: "Nothing was deleted",
                userDescription: "You need to authenticate to delete it.",
                debugDescription: error.localizedDescription,
            )
            return
        }

        do {
            try store.deleteAll()
        } catch {
            deleteError = PresentationError(
                userTitle: "Can't delete it",
                userDescription: "Unable to delete the set-aside vault right now. Please try again.",
                debugDescription: error.localizedDescription,
            )
        }
        reload()
    }
}
