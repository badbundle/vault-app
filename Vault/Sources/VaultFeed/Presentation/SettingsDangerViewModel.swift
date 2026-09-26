import Foundation

/// The Danger Zone: what deleting all data removes and keeps, a confirmation step, then the deletion itself.
///
/// Deleting always goes through `confirming` first, and device authentication after that. Authentication guards
/// against someone using an unattended device; it doesn't make the action safe to use under coercion (MANIFESTO C4),
/// so nothing else belongs here.
@MainActor
@Observable
public final class SettingsDangerViewModel {
    public enum State: Equatable {
        /// Explaining what deleting all data removes and what it keeps.
        case overview
        /// Asking "Delete everything?" before authenticating.
        case confirming
        /// Authenticating, then deleting. This can't be cancelled.
        case deleting
        /// Authentication or deleting failed. The user can try again or go back.
        case failed(PresentationError)
        /// Everything was deleted.
        case deleted
    }

    public private(set) var state: State = .overview
    private let dataModel: VaultDataModel
    private let authenticationService: DeviceAuthenticationService

    public init(dataModel: VaultDataModel, authenticationService: DeviceAuthenticationService) {
        self.dataModel = dataModel
        self.authenticationService = authenticationService
    }

    public var isDeleting: Bool {
        state == .deleting
    }

    /// Whether the "Delete everything?" step is showing, including while deleting and after a failure.
    public var isShowingConfirmation: Bool {
        switch state {
        case .overview: false
        case .confirming, .deleting, .failed, .deleted: true
        }
    }

    public func askToConfirm() {
        guard state == .overview else { return }
        state = .confirming
    }

    public func cancelConfirmation() {
        switch state {
        case .confirming, .failed: state = .overview
        case .overview, .deleting, .deleted: break
        }
    }

    /// Deletes every item and tag, once the user has confirmed and authenticated.
    public func deleteEntireVault() async {
        switch state {
        case .confirming, .failed: break
        case .overview, .deleting, .deleted: return
        }
        state = .deleting

        do {
            try await authenticationService.validateAuthentication(reason: "Delete all data")
        } catch {
            state = .failed(.init(
                userTitle: "Nothing was deleted",
                userDescription: "You need to authenticate to delete your data.",
                debugDescription: error.localizedDescription,
            ))
            return
        }

        do {
            try await dataModel.deleteVault()
        } catch {
            state = .failed(.init(
                userTitle: "Can't delete Vault",
                userDescription: "Unable to delete Vault data right now. Please try again.",
                debugDescription: error.localizedDescription,
            ))
            return
        }
        // Deleting might be really fast, so hold the deleting state long enough to notice. Everything is already
        // gone by now, so being cancelled here isn't a failure.
        try? await Task.sleep(for: .seconds(2))
        state = .deleted
    }
}
