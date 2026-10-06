import Foundation
import TestHelpers
import VaultCore
@testable import VaultFeed
@testable import VaultMac

/// A vault in memory, with fixed phrase keys and no keychain, for a test's data model.
@MainActor
enum MacTestVault {
    /// - Parameters:
    ///   - killphraseKey: The key killphrases are checked with, as the device's keychain would hold it.
    ///   - searchKey: The key search passphrases are checked with.
    static func make(
        killphraseKey: KeyData<32> = .zero(),
        searchKey: KeyData<32> = .zero(),
    ) throws -> (VaultDataModel, VaultStoreSession) {
        let store = try PersistedLocalVaultStore.inMemory()
        let session = VaultStoreSession(target: .plain(store))
        let killphraseKeys = KillphraseKeyStoreMock()
        killphraseKeys.loadOrCreateHandler = { killphraseKey }
        let searchKeys = SearchPassphraseKeyStoreMock()
        searchKeys.loadOrCreateHandler = { searchKey }
        let dataModel = VaultDataModel(
            vaultStore: session,
            vaultTagStore: session,
            vaultImporter: session,
            vaultDeleter: session,
            vaultKillphraseDeleter: session,
            vaultOtpAutofillStore: NoCredentialIdentities(),
            backupPasswordStore: BackupPasswordStoreMock(),
            killphraseKeyStore: killphraseKeys,
            killphraseRehashService: nil,
            searchPassphraseKeyStore: searchKeys,
            searchPassphraseRehashService: nil,
            backupEventLogger: BackupEventLoggerMock(),
        )
        return (dataModel, session)
    }
}
