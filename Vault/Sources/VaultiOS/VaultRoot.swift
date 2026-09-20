import Foundation
import FoundationExtensions
import SwiftSecurity
import VaultFeed
import VaultSettings
#if canImport(WidgetKit)
import WidgetKit
#endif

/// The root entrypoint for the vault application.
///
/// This is the composition root of the application.
public enum VaultRoot {
    // MARK: - Primitives

    @MainActor
    public static let defaults: Defaults = {
        #if DEBUG
        // Marketing screenshots start from clean settings and leave the
        // real ones untouched.
        if ScreenshotMode.isEnabled {
            return ScreenshotMode.makeDefaults()
        }
        #endif
        return .init(userDefaults: .standard)
    }()

    @MainActor
    public static let localSettings: LocalSettings = .init(defaults: defaults)

    public static let timer: some IntervalTimer = IntervalTimerImpl()

    public static let clock: some EpochClock = EpochClockImpl()

    @MainActor
    public static let fileManager: FileManager = .default

    @MainActor
    public static let pasteboard: Pasteboard = .init(SystemPasteboardImpl(clock: clock), localSettings: localSettings)

    // MARK: - Stores

    public static let keychain: Keychain = .default

    public static let secureStorage: some SecureStorage = SecureStorageImpl(keychain: keychain)

    @MainActor
    static let vaultStorageDirectory: URL = VaultSharedStorage.directory(fileManager: fileManager)

    /// Non-nil when the on-disk vault store could not be opened (even
    /// after recovery) and `vaultStore` is an empty in-memory fallback.
    /// The main scene checks this before wiring `setup()` and shows a
    /// failure screen instead of the vault.
    @MainActor
    public private(set) static var vaultStoreLoadFailureMessage: String?

    @MainActor
    public static let vaultStore: PersistedLocalVaultStore = {
        #if DEBUG
        // Likewise the vault: an in-memory one, so the simulator's stored
        // vault is never shown or modified.
        if ScreenshotMode.isEnabled {
            do {
                return try .inMemory()
            } catch {
                fatalError("Unable to create screenshot store: \(error)")
            }
        }
        #endif
        do {
            return try PersistedLocalVaultStoreFactory(storageDirectory: vaultStorageDirectory)
                .makeVaultStoreOrThrow()
        } catch {
            // Fall back to an empty in-memory store instead of crashing at
            // launch: the composition graph stays valid for every consumer
            // and the scene shows a failure screen. The failed store files
            // were archived beside the store by the factory's recovery.
            vaultStoreLoadFailureMessage = error.localizedDescription
            do {
                return try .inMemory()
            } catch {
                // In-memory container creation has no external failure
                // modes; if even this fails the process cannot run.
                fatalError("Unable to create fallback in-memory store: \(error)")
            }
        }
    }()

    public static let backupPasswordStore: some BackupPasswordStore =
        BackupPasswordStoreImpl(secureStorage: secureStorage)

    public static let killphraseKeyStore: some KillphraseKeyStore<KeyData<32>> =
        KillphraseKeyStoreImpl(secureStorage: secureStorage)

    public static let searchPassphraseKeyStore: some SearchPassphraseKeyStore<KeyData<32>> =
        SearchPassphraseKeyStoreImpl(secureStorage: secureStorage)

    public static let vaultOtpAutofillStore: some VaultOTPAutofillStore =
        VaultOTPAutofillStoreImpl(store: RealCredentialIdentityStore())

    @MainActor
    static let killphraseRehashService: KillphraseRehashService = makeKillphraseRehashService()

    @MainActor
    static let searchPassphraseRehashService: SearchPassphraseRehashService = makeSearchPassphraseRehashService()

    @MainActor
    private static func makeKillphraseRehashService() -> KillphraseRehashService {
        // Capture vaultStore (an actor reference, Sendable) into a local
        // so the writer closure can hop straight onto the store actor
        // without re-crossing MainActor on every call.
        let store = vaultStore
        return KillphraseRehashService(
            storeDirectory: vaultStorageDirectory,
            fileManager: fileManager,
            writer: { id, digest in
                try await store.applyKillphraseDigest(itemID: id, digest: digest)
            },
        )
    }

    @MainActor
    private static func makeSearchPassphraseRehashService() -> SearchPassphraseRehashService {
        let store = vaultStore
        return SearchPassphraseRehashService(
            storeDirectory: vaultStorageDirectory,
            fileManager: fileManager,
            writer: { id, digest in
                try await store.applySearchPassphraseDigest(itemID: id, digest: digest)
            },
        )
    }

    @MainActor
    public static let vaultDataModel: VaultDataModel = .init(
        vaultStore: vaultStore,
        vaultTagStore: vaultStore,
        vaultImporter: vaultStore,
        vaultDeleter: vaultStore,
        vaultKillphraseDeleter: vaultStore,
        vaultOtpAutofillStore: vaultOtpAutofillStore,
        backupPasswordStore: backupPasswordStore,
        killphraseKeyStore: killphraseKeyStore,
        killphraseRehashService: killphraseRehashService,
        searchPassphraseKeyStore: searchPassphraseKeyStore,
        searchPassphraseRehashService: searchPassphraseRehashService,
        backupEventLogger: backupEventLogger,
    )

    // MARK: - Previews

    /// Performs the actions in order if it is able.
    ///
    /// We prefer copying text over opening item details.
    /// Therefore, we first of all try to copy text from the available repositories that support
    /// copying and, failing that, we then open the item detail.
    @MainActor
    static let vaultItemPreviewActionHandler: some VaultItemPreviewActionHandler =
        VaultItemPreviewActionHandlerPrefersTextCopy(copyHandlers: [vaultItemCopyHandler])

    /// Available data sources for providing text to copy.
    @MainActor
    public static let vaultItemCopyHandler: some VaultItemCopyActionHandler =
        GenericVaultItemCopyActionHandler(childHandlers: [
            totpPreviewRepository,
            hotpPreviewRepository,
        ])

    @MainActor
    static let secureNotePreviewViewGenerator =
        SecureNotePreviewViewGenerator(viewFactory: SecureNotePreviewViewFactoryImpl())

    @MainActor
    static let encryptedItemPreviewViewGenerator =
        EncryptedItemPreviewViewGenerator(viewFactory: EncryptedItemPreviewViewFactoryImpl())

    @MainActor
    static let otpCodeTimerUpdaterFactory: some OTPCodeTimerUpdaterFactory = OTPCodeTimerUpdaterFactoryImpl(
        timer: timer,
        clock: clock,
    )

    @MainActor
    static let totpPreviewRepository: some TOTPPreviewViewRepository = {
        let repo = TOTPPreviewViewRepositoryImpl(
            clock: clock,
            timer: timer,
            updaterFactory: otpCodeTimerUpdaterFactory,
        )
        vaultDataModel.itemCaches.append(repo)
        return repo
    }()

    /// Ideally this would just vend the generic `some VaultItemPreviewViewGenerator<VaultItem.Payload>`
    /// But that currently gives us a compiler error (only while archiving?!) so let's vend the full (massive) concrete
    /// type for now :(
    @MainActor
    public static let genericVaultItemPreviewViewGenerator =
        GenericVaultItemPreviewViewGenerator(
            totpGenerator: totpPreviewViewGenerator,
            hotpGenerator: hotpPreviewViewGenerator,
            noteGenerator: secureNotePreviewViewGenerator,
            encryptedGenerator: encryptedItemPreviewViewGenerator,
        )

    @MainActor
    static let totpPreviewViewGenerator =
        TOTPPreviewViewGenerator(
            viewFactory: TOTPPreviewViewFactoryImpl(),
            repository: totpPreviewRepository,
        )

    @MainActor
    static let hotpPreviewRepository: some HOTPPreviewViewRepository = {
        let repo = HOTPPreviewViewRepositoryImpl(
            timer: timer,
            store: vaultDataModel,
        )
        vaultDataModel.itemCaches.append(repo)
        return repo
    }()

    @MainActor
    static let hotpPreviewViewGenerator = HOTPPreviewViewGenerator(
        viewFactory: HOTPPreviewViewFactoryImpl(),
        repository: hotpPreviewRepository,
    )

    // MARK: - Misc

    @MainActor
    public static let vaultKeyDeriverFactory: some VaultKeyDeriverFactory = VaultKeyDeriverFactoryImpl()

    @MainActor
    static let backupEventLogger: some BackupEventLogger = BackupEventLoggerImpl(defaults: defaults, clock: clock)

    static let encryptedVaultDecoder: some EncryptedVaultDecoder<KeyData<32>> = EncryptedVaultDecoderImpl()

    @MainActor
    public static let deviceAuthenticationService: DeviceAuthenticationService = .init(policy: .default)

    @MainActor
    static let lockAnimationPresenter = LockAnimationPresenter()

    // MARK: - Auto-Backup

    @MainActor
    static let iCloudDriveProvider: iCloudDriveProvider = .init()

    @MainActor
    public static let autoBackupService: some AutoBackupService = AutoBackupServiceImpl(
        dataModel: vaultDataModel,
        backupEventLogger: backupEventLogger,
        clock: clock,
        defaults: defaults,
        providers: [iCloudDriveProvider],
    )

    @MainActor
    public static let vaultInjector: VaultInjector = .init(
        clock: clock,
        intervalTimer: timer,
        backupEventLogger: backupEventLogger,
        vaultKeyDeriverFactory: vaultKeyDeriverFactory,
        encryptedVaultDecoder: encryptedVaultDecoder,
        autoBackupService: autoBackupService,
        defaults: defaults,
        fileManager: fileManager,
    )

    // MARK: - Setup

    /// Call this at app startup to wire up connections between components.
    @MainActor
    public static func setup() {
        // Wire up auto-backup and widget reloads to trigger when vault data
        // changes. The OTP widget reads items from the shared App Group
        // container and only refreshes when the system or this hook asks it to.
        vaultDataModel.onDataChanged = {
            autoBackupService.notifyDataChanged()
            reloadWidgetTimelines()
        }
        reloadWidgetTimelines()
    }

    @MainActor
    private static func reloadWidgetTimelines() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
