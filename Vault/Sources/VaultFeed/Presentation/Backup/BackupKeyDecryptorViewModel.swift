import Combine
import Foundation
import FoundationExtensions
import VaultBackup
import VaultKeygen

@MainActor
@Observable
public final class BackupKeyDecryptorViewModel {
    public enum DecryptionKeyState: Equatable, Hashable {
        case none
        case error(PresentationError)
        case validDecryptionKey

        public var isSuccess: Bool {
            switch self {
            case .validDecryptionKey: true
            case .none, .error: false
            }
        }

        public var isError: Bool {
            switch self {
            case .error: true
            case .none, .validDecryptionKey: false
            }
        }
    }

    public var enteredPassword = ""
    public private(set) var decryptionKeyState: DecryptionKeyState = .none
    public private(set) var isDecrypting = false
    /// Counts the attempts that failed, so each one is a change the UI sees, even with the same error as the last.
    public private(set) var failedAttemptCount = 0
    private let decryptedVaultSubject: PassthroughSubject<VaultApplicationPayload, Never>

    private let encryptedVault: EncryptedVault
    private let keyDeriverFactory: any VaultKeyDeriverFactory
    private let encryptedVaultDecoder: any EncryptedVaultDecoder<KeyData<32>>

    public init(
        encryptedVault: EncryptedVault,
        keyDeriverFactory: any VaultKeyDeriverFactory,
        encryptedVaultDecoder: any EncryptedVaultDecoder<KeyData<32>>,
        decryptedVaultSubject: PassthroughSubject<VaultApplicationPayload, Never>,
    ) {
        self.encryptedVault = encryptedVault
        self.keyDeriverFactory = keyDeriverFactory
        self.encryptedVaultDecoder = encryptedVaultDecoder
        self.decryptedVaultSubject = decryptedVaultSubject
    }

    private struct MissingPasswordError: Error, LocalizedError {
        var errorDescription: String? {
            "Password Required"
        }

        var failureReason: String? {
            "The password cannot be empty"
        }
    }

    public var canAttemptDecryption: Bool {
        enteredPassword.isNotEmpty
    }

    public func attemptDecryption() async {
        do {
            guard enteredPassword.isNotEmpty else { throw MissingPasswordError() }
            decryptionKeyState = .none
            isDecrypting = true
            defer { isDecrypting = false }
            let signature = try VaultKeyDeriver.Signature(tryFromString: encryptedVault.keygenSignature)
            let keyDeriver = keyDeriverFactory.lookupVaultKeyDeriver(signature: signature)
            let password = enteredPassword
            let salt = encryptedVault.keygenSalt
            let generatedKey = try await Task.background {
                try keyDeriver.recreateEncryptionKey(password: password, salt: salt)
            }
            // Cancelling only stops the key deriver between its stages, so a cancelled attempt can still finish
            // deriving the key. Drop it here, before it decrypts the backup or reaches the import.
            try Task.checkCancellation()
            let vaultApplicationPayload = try encryptedVaultDecoder.decryptAndDecode(
                key: generatedKey.key,
                encryptedVault: encryptedVault,
            )
            decryptionKeyState = .validDecryptionKey
            decryptedVaultSubject.send(vaultApplicationPayload)
        } catch is CancellationError {
            // The user cancelled, so there's nothing to say.
            decryptionKeyState = .none
        } catch let error as any LocalizedError {
            decryptionKeyState = .error(.init(localizedError: error))
            failedAttemptCount += 1
        } catch {
            decryptionKeyState = .error(PresentationError(
                userTitle: "Password Generation Error",
                userDescription: "Please try again.",
                debugDescription: error.localizedDescription,
            ))
            failedAttemptCount += 1
        }
    }
}
