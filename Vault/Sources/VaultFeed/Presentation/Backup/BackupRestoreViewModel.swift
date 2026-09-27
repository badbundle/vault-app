import Foundation

/// View model for the backup restoration view.
///
/// The page stays locked until the user passes device authentication, whether or not a backup
/// password is set: restoring can replace the whole vault. That guards against someone restoring
/// over the vault on a device left unlocked and unattended, and against nothing else. Anyone who
/// can make the user unlock the device can make them pass this too (MANIFESTO C4).
///
/// On a device with no passcode there's nothing to authenticate with, so the page stays locked and says a passcode
/// is needed, as the Backup Password sheet and the Danger Zone do.
@MainActor
@Observable
public final class BackupRestoreViewModel {
    public let strings = Strings()
    public private(set) var permissionState: PermissionState
    private let authenticationService: DeviceAuthenticationService

    public init(authenticationService: DeviceAuthenticationService) {
        self.authenticationService = authenticationService
        permissionState = authenticationService.lockedPermissionState
    }

    /// Asks the user to authenticate, and unlocks the page if they do.
    public func authenticate() async {
        guard authenticationService.canAuthenticate else {
            permissionState = .unavailable
            return
        }
        do {
            try await authenticationService.validateAuthentication(reason: "Authenticate to restore a backup.")
            permissionState = .allowed
        } catch {
            permissionState = .denied
        }
    }

    /// Locks the page again, so the next visit has to authenticate.
    ///
    /// This happens whenever the app goes to the background too, so a passcode set up in the Settings app in the
    /// meantime is noticed on return.
    public func lock() {
        permissionState = authenticationService.lockedPermissionState
    }
}

// MARK: - Strings

extension BackupRestoreViewModel {
    @MainActor
    public struct Strings {
        init() {}

        public let homeTitle = localized(key: "backupRestore.title")
        public let backupPasswordImportTitle = localized(key: "backupPasswordState.import.title")
    }
}
