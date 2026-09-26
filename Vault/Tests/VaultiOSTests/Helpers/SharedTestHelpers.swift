import Foundation
import FoundationExtensions
import SwiftUI
import VaultCore
import VaultFeed
import VaultSettings
@testable import VaultiOS

@MainActor
func anyVaultDataModel(
    vaultStore: any VaultStore = VaultStoreStub(),
    vaultTagStore: any VaultTagStore = VaultTagStoreStub(),
    vaultImporter: any VaultStoreImporter = VaultStoreImporterMock(),
    vaultDeleter: any VaultStoreDeleter = VaultStoreDeleterMock(),
    vaultKillphraseDeleter: any VaultStoreKillphraseDeleter = VaultStoreKillphraseDeleterMock(),
    vaultOtpAutofillStore: any VaultOTPAutofillStore = VaultOTPAutofillStoreMock(),
    backupPasswordStore: any BackupPasswordStore = BackupPasswordStoreMock(),
    killphraseKeyStore: (any KillphraseKeyStore<KeyData<32>>)? = nil,
    killphraseRehashService: KillphraseRehashService? = nil,
    searchPassphraseKeyStore: (any SearchPassphraseKeyStore<KeyData<32>>)? = nil,
    searchPassphraseRehashService: SearchPassphraseRehashService? = nil,
    backupEventLogger: any BackupEventLogger = BackupEventLoggerMock(),
) -> VaultDataModel {
    VaultDataModel(
        vaultStore: vaultStore,
        vaultTagStore: vaultTagStore,
        vaultImporter: vaultImporter,
        vaultDeleter: vaultDeleter,
        vaultKillphraseDeleter: vaultKillphraseDeleter,
        vaultOtpAutofillStore: vaultOtpAutofillStore,
        backupPasswordStore: backupPasswordStore,
        killphraseKeyStore: killphraseKeyStore ?? StubKillphraseKeyStore(),
        killphraseRehashService: killphraseRehashService,
        searchPassphraseKeyStore: searchPassphraseKeyStore ?? StubSearchPassphraseKeyStore(),
        searchPassphraseRehashService: searchPassphraseRehashService,
        backupEventLogger: backupEventLogger,
    )
}

/// Default no-op key store for VaultDataModel tests that don't exercise
/// the killphrase digest path. Returns a fixed all-zero key so
/// `loadOrCreate` never fatal-errors when called from `setup()`.
struct StubKillphraseKeyStore: KillphraseKeyStore {
    func loadOrCreate() async throws -> KeyData<32> {
        .zero()
    }
}

/// Default no-op key store for VaultDataModel tests that don't exercise
/// the search-passphrase digest path.
struct StubSearchPassphraseKeyStore: SearchPassphraseKeyStore {
    func loadOrCreate() async throws -> KeyData<32> {
        .zero()
    }
}

@MainActor
func anyVaultInjector(vaultStoreArchives: any VaultStoreArchiving = NoVaultStoreArchives()) -> VaultInjector {
    VaultInjector(
        clock: EpochClockMock(currentTime: 100),
        intervalTimer: IntervalTimerMock(),
        backupEventLogger: BackupEventLoggerMock(),
        vaultKeyDeriverFactory: VaultKeyDeriverFactoryMock(),
        encryptedVaultDecoder: EncryptedVaultDecoderMock(),
        autoBackupService: AutoBackupServiceMock(status: .disabled, configuration: .init()),
        defaults: Defaults(userDefaults: .standard),
        fileManager: .default,
        vaultStoreArchives: vaultStoreArchives,
    )
}

struct TestError: Error {}

func anyVaultItemTag(
    id: UUID = UUID(),
    name: String = "name",
    color: VaultItemColor = .tagDefault,
    iconName: String = VaultItemTag.defaultIconName,
) -> VaultItemTag {
    VaultItemTag(id: .init(id: id), name: name, color: color, iconName: iconName)
}

func anySecureNote(title: String = "any") -> SecureNote {
    .init(title: title, contents: "This is my note", format: .markdown)
}

func anyVaultItemMetadata(
    lockState: VaultItemLockState = .notLocked,
) -> VaultItem.Metadata {
    .init(
        id: Identifier<VaultItem>(),
        created: Date(),
        updated: Date(),
        relativeOrder: .min,
        userDescription: "any",
        tags: [],
        visibility: .always,
        searchableLevel: .full,
        searchPassphrase: nil,
        killphrase: nil,
        lockState: lockState,
        color: .black,
        showInQuickType: true,
        previewMode: .titleAndFirstLine,
    )
}

func anyOTPVaultItem(
    type: OTPAuthType,
    secret: OTPAuthSecret = .empty(),
    algorithm: OTPAuthAlgorithm = .sha256,
    digits: OTPAuthDigits = .init(value: 6),
    color: VaultItemColor? = nil,
) -> VaultItem {
    let code = OTPAuthCode(
        type: type,
        data: .init(
            secret: secret,
            algorithm: algorithm,
            digits: digits,
            accountName: "my account name",
            issuer: "my issuer",
        ),
    )
    return VaultItem(
        metadata: .init(
            id: Identifier<VaultItem>(),
            created: Date(),
            updated: Date(),
            relativeOrder: .min,
            userDescription: "any",
            tags: [],
            visibility: .always,
            searchableLevel: .full,
            searchPassphrase: nil,
            killphrase: nil,
            lockState: .notLocked,
            color: color,
            showInQuickType: true,
            previewMode: .titleAndFirstLine,
        ),
        item: .otpCode(code),
    )
}

extension VaultItemPreviewViewGeneratorMock {
    static func defaultMock() -> VaultItemPreviewViewGeneratorMock {
        mockGenerating { _, _, _ in
            Text("Preview View")
        }
    }

    /// The preview view will be generated with the provided view.
    static func mockGenerating(
        @ViewBuilder view: @escaping (PreviewItem, VaultItem.Metadata, VaultItemViewBehaviour)
            -> some View,
    ) -> VaultItemPreviewViewGeneratorMock {
        let s = VaultItemPreviewViewGeneratorMock()
        s.makeVaultPreviewViewHandler = { item, metadata, behaviour in
            AnyView(
                view(item, metadata, behaviour),
            )
        }
        return s
    }
}

func uniqueCode() -> OTPAuthCode {
    let randomData = Data.random(count: 50)
    return OTPAuthCode(
        type: .totp(),
        data: .init(
            secret: .init(data: randomData, format: .base32),
            accountName: "Some Account",
        ),
    )
}

func uniqueVaultItem() -> VaultItem {
    VaultItem(
        metadata: uniqueMetadata(),
        item: .otpCode(uniqueCode()),
    )
}

func anySecureNote() -> SecureNote {
    .init(title: "Hello World", contents: "This is my note", format: .markdown)
}

func anyEncryptedItem() -> EncryptedItem {
    .init(
        version: "1.0.0",
        title: "Hello World",
        data: Data(repeating: 0x03, count: 10),
        authentication: Data(repeating: 0x03, count: 10),
        encryptionIV: Data(repeating: 0x03, count: 10),
        keygenSalt: Data(repeating: 0x03, count: 10),
        keygenSignature: "my sig",
    )
}

func uniqueMetadata(id: Identifier<VaultItem> = Identifier<VaultItem>()) -> VaultItem.Metadata {
    .init(
        id: id,
        created: Date(),
        updated: Date(),
        relativeOrder: .min,
        userDescription: "any",
        tags: [],
        visibility: .always,
        searchableLevel: .full,
        searchPassphrase: nil,
        killphrase: nil,
        lockState: .notLocked,
        color: nil,
        showInQuickType: true,
        previewMode: .titleAndFirstLine,
    )
}

func forceRunLoopAdvance() {
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
}
