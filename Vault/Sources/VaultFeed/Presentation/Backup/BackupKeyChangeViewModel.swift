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
    public internal(set) var permissionState: PermissionState = .undetermined
    public private(set) var newPassword: NewPasswordState = .initial
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
    }

    public var passwordConfirmMatches: Bool {
        newlyEnteredPassword == newlyEnteredPasswordConfirm
    }

    public var canSetBackupPassword: Bool {
        !newPassword.isLoading && passwordConfirmMatches && newlyEnteredPassword.isNotBlank
    }

    public var encryptionKeyDeriverSignature: VaultKeyDeriver.Signature {
        encryptionKeyDeriver.signature
    }

    public func onAppear() async {
        do {
            try await authenticationService
                .validateAuthentication(reason: "Authenticate to change the backup password.")
            permissionState = .allowed
        } catch {
            permissionState = .denied
        }
    }

    public func didDisappear() {
        permissionState = .undetermined
        // Don't retain the plaintext password beyond the lifetime of the
        // screen that collected it.
        newlyEnteredPassword = ""
        newlyEnteredPasswordConfirm = ""
    }

    private struct PasswordConfirmError: Error {}

    public func saveEnteredPassword() async {
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
            try await dataModel.store(backupPassword: createdBackupPassword)
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
