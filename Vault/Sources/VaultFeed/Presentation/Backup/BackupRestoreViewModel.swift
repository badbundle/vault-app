import Foundation

/// View model for the backup restoration view.
///
/// The page stays locked until the user passes device authentication, whether or not a backup
/// password is set: restoring can replace the whole vault. That guards against someone restoring
/// over the vault on a device left unlocked and unattended, and against nothing else. Anyone who
/// can make the user unlock the device can make them pass this too (MANIFESTO C4).
@MainActor
@Observable
public final class BackupRestoreViewModel {
    public let strings = Strings()
    public private(set) var permissionState: PermissionState = .undetermined
    private let authenticationService: DeviceAuthenticationService

    public init(authenticationService: DeviceAuthenticationService) {
        self.authenticationService = authenticationService
    }

    /// Asks the user to authenticate, and unlocks the page if they do.
    public func authenticate() async {
        do {
            try await authenticationService.validateAuthentication(reason: "Authenticate to restore a backup.")
            permissionState = .allowed
        } catch {
            permissionState = .denied
        }
    }

    /// Locks the page again, so the next visit has to authenticate.
    public func lock() {
        permissionState = .undetermined
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
