import Foundation
import VaultCore
import VaultKeygen

@MainActor
@Observable
public final class EncryptedItemDetailViewModel {
    public let item: EncryptedItem
    public let metadata: VaultItem.Metadata
    private let keyDeriverFactory: any VaultKeyDeriverFactory
    public var enteredEncryptionPassword = ""
    public private(set) var state: State = .base

    public enum State: Equatable {
        case base
        case decrypting
        case decrypted(VaultItem.Payload, DerivedEncryptionKey)
        case decryptionError(PresentationError)

        public var preventsUserInteraction: Bool {
            switch self {
            case .decrypting: true
            default: false
            }
        }

        public var presentationError: PresentationError? {
            switch self {
            case let .decryptionError(error): error
            default: nil
            }
        }
    }

    public init(item: EncryptedItem, metadata: VaultItem.Metadata, keyDeriverFactory: any VaultKeyDeriverFactory) {
        self.item = item
        self.metadata = metadata
        self.keyDeriverFactory = keyDeriverFactory
    }

    /// Once the item is decrypted it's on its way to being shown, so there's nothing more to decrypt.
    public var canStartDecryption: Bool {
        switch state {
        case .base, .decryptionError: enteredEncryptionPassword.isNotBlank
        case .decrypting, .decrypted: false
        }
    }

    /// Whether the password has decrypted the item, which is now being opened.
    public var isDecrypted: Bool {
        if case .decrypted = state {
            true
        } else {
            false
        }
    }

    public var isLoading: Bool {
        state == .decrypting
    }

    public func resetState() {
        state = .base
    }

    public func startDecryption() async {
        do {
            guard canStartDecryption else { return }
            state = .decrypting

            let signature = try VaultKeyDeriver.Signature(tryFromString: item.keygenSignature)
            let keyDeriver = keyDeriverFactory.lookupVaultKeyDeriver(signature: signature)
            let password = enteredEncryptionPassword
            let salt = item.keygenSalt
            let generatedPassword = try await Task.background {
                try keyDeriver.recreateEncryptionKey(password: password, salt: salt)
            }
            let action = attemptDecryption(password: generatedPassword)
            switch action {
            case let .unsupportedItemError(identifier):
                throw PresentationError(
                    userTitle: "Error",
                    userDescription: "Your password was correct, but the item that was encrypted is not known to Vault. We can't display it.",
                    debugDescription: "Unknown item error. Item identifier was '\(identifier)'.",
                )
            case let .itemDataError(error):
                throw error // rethrow so state is set below
            case .promptForDifferentPassword:
                throw PresentationError(
                    userTitle: "Incorrect Password",
                    userDescription: "Your password was not recognized, please try again.",
                    debugDescription: "promptForDifferentPassword",
                )
            case let .decrypted(item):
                state = .decrypted(item, generatedPassword)
            }
        } catch let localized as any LocalizedError {
            state = .decryptionError(PresentationError(localizedError: localized))
        } catch {
            state = .decryptionError(PresentationError(
                userTitle: "Error",
                userDescription: "Unable to decrypt this item. Please try again.",
                debugDescription: error.localizedDescription,
            ))
        }
    }

    private enum Action {
        /// The item is of a kind that we cannot identify.
        case unsupportedItemError(identifier: String)
        /// Decryption was successful, but the data is corrupt.
        case itemDataError(any Error)
        case promptForDifferentPassword
        case decrypted(VaultItem.Payload)
    }

    private func attemptDecryption(password: DerivedEncryptionKey?) -> Action {
        guard let password else { return .promptForDifferentPassword }
        let decryptor = VaultItemDecryptor(key: password)
        do {
            let itemIdentifier = try decryptor.decryptItemIdentifier(item: item)
            switch itemIdentifier {
            case VaultIdentifiers.Item.secureNote:
                let decryptedNote: SecureNote = try decryptor.decrypt(
                    item: item,
                    expectedItemIdentifier: VaultIdentifiers.Item.secureNote,
                )
                return .decrypted(.secureNote(decryptedNote))
            case VaultIdentifiers.Item.recoveryPhrase:
                let decryptedPhrase: RecoveryPhrase = try decryptor.decrypt(
                    item: item,
                    expectedItemIdentifier: VaultIdentifiers.Item.recoveryPhrase,
                )
                return .decrypted(.recoveryPhrase(decryptedPhrase))
            default:
                return .unsupportedItemError(identifier: itemIdentifier)
            }
        } catch VaultItemDecryptor.Error.decryptionFailed {
            return .promptForDifferentPassword
        } catch let VaultItemDecryptor.Error.mismatchedItemIdentifier(_, actual) {
            return .unsupportedItemError(identifier: actual)
        } catch {
            return .itemDataError(error)
        }
    }
}
