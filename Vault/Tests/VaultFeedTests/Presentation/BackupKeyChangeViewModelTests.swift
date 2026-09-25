import CryptoEngine
import Foundation
import FoundationExtensions
import TestHelpers
import Testing
import VaultKeygen
@testable import VaultFeed

@MainActor
struct BackupKeyChangeViewModelTests {
    @Test
    func init_hasNoSideEffects() {
        let store = BackupPasswordStoreMock()
        let dataModel = anyVaultDataModel(backupPasswordStore: store)
        _ = makeSUT(dataModel: dataModel)

        #expect(store.fetchPasswordCallCount == 0)
        #expect(store.setCallCount == 0)
    }

    @Test
    func init_initialPermissionStateLoading() {
        let sut = makeSUT()

        #expect(sut.permissionState == .undetermined)
    }

    @Test
    func onAppear_permissonStateAllowedIfNoError() async {
        let authenticationService = DeviceAuthenticationService(policy: .alwaysAllow)
        let sut = makeSUT(authenticationService: authenticationService)

        await sut.onAppear()

        #expect(sut.permissionState == .allowed)
    }

    @Test
    func onAppear_permissionStateDeniedIfError() async {
        let authenticationService = DeviceAuthenticationService(policy: .alwaysDeny)
        let sut = makeSUT(authenticationService: authenticationService)

        await sut.onAppear()

        #expect(sut.permissionState == .denied)
    }

    @Test
    func onAppear_allowedLoadsCurrentPasswordStatus() async {
        let store = BackupPasswordStoreMock()
        let metadata = BackupPasswordMetadata(lastSetDate: Date(timeIntervalSince1970: 1_700_000_000))
        store.fetchPasswordMetadataHandler = { metadata }
        let dataModel = anyVaultDataModel(backupPasswordStore: store)
        let sut = makeSUT(dataModel: dataModel)

        await sut.onAppear()

        #expect(sut.currentPasswordStatus == .set(metadata))
        #expect(store.fetchPasswordCallCount == 0)
    }

    @Test
    func onAppear_deniedDoesNotLoadCurrentPasswordStatus() async {
        let store = BackupPasswordStoreMock()
        store.fetchPasswordMetadataHandler = { .init(lastSetDate: nil) }
        let dataModel = anyVaultDataModel(backupPasswordStore: store)
        let sut = makeSUT(
            dataModel: dataModel,
            authenticationService: DeviceAuthenticationService(policy: .alwaysDeny),
        )

        await sut.onAppear()

        #expect(sut.currentPasswordStatus == .unknown)
        #expect(store.fetchPasswordMetadataCallCount == 0)
    }

    @Test
    func loadExistingPassword_callsLoadFromDataModel() async {
        let store = BackupPasswordStoreMock()
        let password = randomBackupPassword()
        store.fetchPasswordHandler = { password }
        let dataModel = anyVaultDataModel(backupPasswordStore: store)
        let sut = makeSUT(dataModel: dataModel)

        await sut.loadExistingPassword()

        #expect(store.fetchPasswordCallCount == 1)
    }

    @Test
    func saveEnteredPassword_isPasswordConfirmErrorIfPasswordsDoNotMatch() async {
        let sut = makeSUT()

        sut.newlyEnteredPassword = "hello"
        sut.newlyEnteredPasswordConfirm = "world"

        await sut.saveEnteredPassword()

        #expect(sut.newPassword == .passwordConfirmError)
    }

    @Test
    func saveEnteredPassword_isKeygenErrorIfGenerationError() async {
        let deriverFactory = VaultKeyDeriverFactoryMock()
        deriverFactory.makeVaultBackupKeyDeriverHandler = {
            VaultKeyDeriver(deriver: KeyDeriverErroring(), signature: .testing)
        }
        let sut = makeSUT(deriverFactory: deriverFactory)

        sut.newlyEnteredPassword = "hello"
        sut.newlyEnteredPasswordConfirm = "hello"

        await sut.saveEnteredPassword()

        #expect(sut.newPassword == .keygenError)
    }

    @Test
    func saveEnteredPassword_successSetsNewPasswordStateToSuccess() async {
        let sut = makeSUT()

        sut.newlyEnteredPassword = "hello"
        sut.newlyEnteredPasswordConfirm = "hello"

        await sut.saveEnteredPassword()

        #expect(sut.newPassword == .success)
    }

    @Test
    func saveEnteredPassword_successUpdatesCurrentPasswordStatus() async {
        let store = BackupPasswordStoreMock()
        let metadata = BackupPasswordMetadata(lastSetDate: Date(timeIntervalSince1970: 1_700_000_000))
        store.fetchPasswordMetadataHandler = { metadata }
        let sut = makeSUT(dataModel: anyVaultDataModel(backupPasswordStore: store))

        sut.newlyEnteredPassword = "hello"
        sut.newlyEnteredPasswordConfirm = "hello"

        await sut.saveEnteredPassword()

        #expect(sut.currentPasswordStatus == .set(metadata))
    }

    @Test
    func saveEnteredPassword_firstPasswordDoesNotReplaceExisting() async {
        let store = BackupPasswordStoreMock()
        store.fetchPasswordMetadataHandler = { nil }
        let dataModel = anyVaultDataModel(backupPasswordStore: store)
        let sut = makeSUT(dataModel: dataModel)
        await sut.onAppear()
        store.fetchPasswordMetadataHandler = { .init(lastSetDate: nil) }

        sut.newlyEnteredPassword = "hello"
        sut.newlyEnteredPasswordConfirm = "hello"

        await sut.saveEnteredPassword()

        #expect(sut.didReplaceExistingPassword == false)
    }

    @Test
    func saveEnteredPassword_replacingPasswordReplacesExisting() async {
        let store = BackupPasswordStoreMock()
        store.fetchPasswordMetadataHandler = { .init(lastSetDate: Date(timeIntervalSince1970: 1_700_000_000)) }
        let dataModel = anyVaultDataModel(backupPasswordStore: store)
        let sut = makeSUT(dataModel: dataModel)
        await sut.onAppear()

        sut.newlyEnteredPassword = "hello"
        sut.newlyEnteredPasswordConfirm = "hello"

        await sut.saveEnteredPassword()

        #expect(sut.didReplaceExistingPassword == true)
    }

    @Test
    func saveEnteredPassword_keygenErrorDoesNotReplaceExisting() async {
        let store = BackupPasswordStoreMock()
        store.fetchPasswordMetadataHandler = { .init(lastSetDate: nil) }
        let deriverFactory = VaultKeyDeriverFactoryMock()
        deriverFactory.makeVaultBackupKeyDeriverHandler = {
            VaultKeyDeriver(deriver: KeyDeriverErroring(), signature: .testing)
        }
        let sut = makeSUT(dataModel: anyVaultDataModel(backupPasswordStore: store), deriverFactory: deriverFactory)
        await sut.onAppear()

        sut.newlyEnteredPassword = "hello"
        sut.newlyEnteredPasswordConfirm = "hello"

        await sut.saveEnteredPassword()

        #expect(sut.didReplaceExistingPassword == false)
    }

    @Test
    func saveEnteredPassword_successResetsEnteredPassword() async {
        let sut = makeSUT()

        sut.newlyEnteredPassword = "hello"
        sut.newlyEnteredPasswordConfirm = "hello"

        await sut.saveEnteredPassword()

        #expect(sut.newlyEnteredPassword == "")
        #expect(sut.newlyEnteredPasswordConfirm == "")
    }

    @Test
    func saveEnteredPassword_cancelledBeforeStore_setsKeygenCancelledAndDoesNotStore() async {
        let store = BackupPasswordStoreMock()
        let dataModel = anyVaultDataModel(backupPasswordStore: store)
        let sut = makeSUT(dataModel: dataModel)

        sut.newlyEnteredPassword = "hello"
        sut.newlyEnteredPasswordConfirm = "hello"

        let task = Task { await sut.saveEnteredPassword() }
        // Cancel before the task body has had a chance to run: the save
        // must observe the cancellation and never replace the stored
        // backup password.
        task.cancel()
        await task.value

        #expect(sut.newPassword == .keygenCancelled)
        #expect(store.setCallCount == 0)
    }

    @Test
    func saveEnteredPassword_cancelled_clearsEnteredPasswords() async {
        let sut = makeSUT()

        sut.newlyEnteredPassword = "hello"
        sut.newlyEnteredPasswordConfirm = "hello"

        let task = Task { await sut.saveEnteredPassword() }
        task.cancel()
        await task.value

        #expect(sut.newlyEnteredPassword == "")
        #expect(sut.newlyEnteredPasswordConfirm == "")
    }

    @Test
    func saveEnteredPassword_keygenError_clearsEnteredPasswords() async {
        let deriverFactory = VaultKeyDeriverFactoryMock()
        deriverFactory.makeVaultBackupKeyDeriverHandler = {
            VaultKeyDeriver(deriver: KeyDeriverErroring(), signature: .testing)
        }
        let sut = makeSUT(deriverFactory: deriverFactory)

        sut.newlyEnteredPassword = "hello"
        sut.newlyEnteredPasswordConfirm = "hello"

        await sut.saveEnteredPassword()

        #expect(sut.newlyEnteredPassword == "")
        #expect(sut.newlyEnteredPasswordConfirm == "")
    }

    @Test
    func saveEnteredPassword_passwordConfirmError_retainsEnteredPasswords() async {
        let sut = makeSUT()

        sut.newlyEnteredPassword = "hello"
        sut.newlyEnteredPasswordConfirm = "world"

        await sut.saveEnteredPassword()

        // The user is mid-correction with the view still frontmost, so
        // the entered text deliberately survives this error.
        #expect(sut.newlyEnteredPassword == "hello")
        #expect(sut.newlyEnteredPasswordConfirm == "world")
    }

    @Test
    func didDisappear_clearsEnteredPasswords() {
        let sut = makeSUT()

        sut.newlyEnteredPassword = "hello"
        sut.newlyEnteredPasswordConfirm = "hello"

        sut.didDisappear()

        #expect(sut.newlyEnteredPassword == "")
        #expect(sut.newlyEnteredPasswordConfirm == "")
    }
}

// MARK: - Helpers

extension BackupKeyChangeViewModelTests {
    @MainActor
    private func makeSUT(
        dataModel: VaultDataModel = VaultDataModel(
            vaultStore: VaultStoreStub(),
            vaultTagStore: VaultTagStoreStub(),
            vaultImporter: VaultStoreImporterMock(),
            vaultDeleter: VaultStoreDeleterMock(),
            vaultKillphraseDeleter: VaultStoreKillphraseDeleterMock(),
            vaultOtpAutofillStore: VaultOTPAutofillStoreMock(),
            backupPasswordStore: BackupPasswordStoreMock(),
            killphraseKeyStore: StubKillphraseKeyStore(),
            killphraseRehashService: nil,
            searchPassphraseKeyStore: StubSearchPassphraseKeyStore(),
            searchPassphraseRehashService: nil,
            backupEventLogger: BackupEventLoggerMock(),
        ),
        authenticationService: DeviceAuthenticationService =
            DeviceAuthenticationService(policy: DeviceAuthenticationPolicyAlwaysAllow()),
        deriverFactory: any VaultKeyDeriverFactory = .testing,
    ) -> BackupKeyChangeViewModel {
        BackupKeyChangeViewModel(
            dataModel: dataModel,
            authenticationService: authenticationService,
            deriverFactory: deriverFactory,
        )
    }

    private func anyBackupPassword() -> DerivedEncryptionKey {
        DerivedEncryptionKey(key: .repeating(byte: 0x45), salt: Data(), keyDervier: .testing)
    }

    private func randomBackupPassword() -> DerivedEncryptionKey {
        DerivedEncryptionKey(key: .random(), salt: Data(), keyDervier: .testing)
    }

    private struct KeyDeriverErroring: KeyDeriver {
        var uniqueAlgorithmIdentifier: String {
            "err"
        }

        func key(password _: Data, salt _: Data) throws -> KeyData<32> {
            struct Err: Error {}
            throw Err()
        }
    }
}
