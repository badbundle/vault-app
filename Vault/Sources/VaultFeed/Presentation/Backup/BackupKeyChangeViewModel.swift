import Foundation
import FoundationExtensions
import VaultBackup
import VaultKeygen

@MainActor
@Observable
public final class BackupKeyChangeViewModel {
    public enum NewPasswordState: Equatable, Hashable {
        case initial
        case creating
        case keygenError
        case keygenCancelled
        case passwordConfirmError
        case success

        public var isLoading: Bool {
            switch self {
            case .initial, .keygenError, .keygenCancelled, .passwordConfirmError, .success: false
            case .creating: true
            }
        }
    }

    public var newlyEnteredPassword = ""
    public var newlyEnteredPasswordConfirm = ""
    public internal(set) var permissionState: PermissionState
    public private(set) var newPassword: NewPasswordState = .initial
    /// Whether the password saved by `saveEnteredPassword()` replaced an existing one, so the
    /// confirmation can point out that older backups still need the old password.
    public private(set) var didReplaceExistingPassword = false
    private let encryptionKeyDeriver: VaultKeyDeriver
    private let authenticationService: DeviceAuthenticationService
    private let dataModel: VaultDataModel

    public init(
        dataModel: VaultDataModel,
        authenticationService: DeviceAuthenticationService,
        deriverFactory: some VaultKeyDeriverFactory,
    ) {
        self.authenticationService = authenticationService
        self.dataModel = dataModel
        encryptionKeyDeriver = deriverFactory.makeVaultBackupKeyDeriver()
        permissionState = authenticationService.lockedPermissionState
    }

    public var passwordConfirmMatches: Bool {
        newlyEnteredPassword == newlyEnteredPasswordConfirm
    }

    /// The rule the new password breaks, once something's been typed.
    ///
    /// A new backup password follows the App Lock Password's rules (`AppLockPasswordRules`): anyone with a copy of a
    /// backup can try passwords on their own computers, as fast as the key derivation allows. A password set before
    /// the rules applied is kept.
    public var newPasswordProblem: AppLockPasswordRules.Problem? {
        guard newlyEnteredPassword.isNotEmpty else { return nil }
        return AppLockPasswordRules.problem(with: newlyEnteredPassword)
    }

    public var canSetBackupPassword: Bool {
        !newPassword.isLoading && passwordConfirmMatches
            && AppLockPasswordRules.problem(with: newlyEnteredPassword) == nil
    }

    public var encryptionKeyDeriverSignature: VaultKeyDeriver.Signature {
        encryptionKeyDeriver.signature
    }

    /// Whether a backup password is already set, and when.
    public var currentPasswordStatus: VaultDataModel.BackupPasswordStatus {
        dataModel.backupPasswordStatus
    }

    /// Asks the user to authenticate, and unlocks the sheet if they do. On a device with no passcode there's nothing
    /// to authenticate with, so it stays locked and says a passcode is needed, as Restore and the Danger Zone do.
    public func onAppear() async {
        guard authenticationService.canAuthenticate else {
            permissionState = .unavailable
            return
        }
        do {
            try await authenticationService
                .validateAuthentication(reason: "Authenticate to change the backup password.")
            permissionState = .allowed
            await dataModel.loadBackupPasswordStatus()
        } catch {
            permissionState = .denied
        }
    }

    public func didDisappear() {
        permissionState = authenticationService.lockedPermissionState
        // Don't retain the plaintext password beyond the lifetime of the
        // screen that collected it.
        newlyEnteredPassword = ""
        newlyEnteredPasswordConfirm = ""
    }

    private struct PasswordConfirmError: Error {}

    public func saveEnteredPassword() async {
        // The form doesn't offer to save a password that breaks the rules.
        guard AppLockPasswordRules.problem(with: newlyEnteredPassword) == nil else { return }
        do {
            guard newlyEnteredPassword == newlyEnteredPasswordConfirm else {
                throw PasswordConfirmError()
            }

            newPassword = .creating
            let password = newlyEnteredPassword
            let createdBackupPassword = try await Task.background {
                try self.encryptionKeyDeriver.createEncryptionKey(password: password)
            }
            // The KDF body is synchronous, so cancellation cannot
            // interrupt it mid-derivation — make it authoritative here,
            // before the derived key replaces the stored password.
            try Task.checkCancellation()
            let replacesExistingPassword = currentPasswordStatus.isSet
            try await dataModel.store(backupPassword: createdBackupPassword)
            didReplaceExistingPassword = replacesExistingPassword
            newPassword = .success
            newlyEnteredPassword = ""
            newlyEnteredPasswordConfirm = ""
        } catch is PasswordConfirmError {
            // Keep the entered passwords: the user is mid-correction and
            // the view is still frontmost.
            newPassword = .passwordConfirmError
        } catch is CancellationError {
            newPassword = .keygenCancelled
            newlyEnteredPassword = ""
            newlyEnteredPasswordConfirm = ""
        } catch {
            newPassword = .keygenError
            newlyEnteredPassword = ""
            newlyEnteredPasswordConfirm = ""
        }
    }

    public func loadExistingPassword() async {
        await dataModel.loadBackupPassword()
    }
}
