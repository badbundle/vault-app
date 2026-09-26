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

    /// The App Group's defaults, for the settings the extensions read too, such as Clear Clipboard.
    @MainActor
    public static let sharedDefaults: Defaults = {
        #if DEBUG
        // Screenshots keep every setting in their own suite, away from the real ones.
        if ScreenshotMode.isEnabled {
            return defaults
        }
        #endif
        return .init(userDefaults: VaultSharedStorage.userDefaults())
    }()

    @MainActor
    public static let localSettings: LocalSettings = .init(defaults: defaults, sharedDefaults: sharedDefaults)

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
    /// after recovery) and `plainVaultStore` is an empty in-memory fallback,
    /// or when how the vault is stored couldn't be worked out.
    /// The main scene checks this before wiring `setup()` and shows a
    /// failure screen instead of the vault.
    @MainActor
    public private(set) static var vaultStoreLoadFailureMessage: String?

    /// Whether this is an app extension (AutoFill), rather than the app.
    static let isAppExtension = Bundle.main.bundleURL.pathExtension == "appex"

    /// How the vault was stored on this device when the process started: in
    /// the plain SQLite store, or encrypted with the App Lock Password. Or
    /// `erasing`, if the app was stopped in the middle of an erase: no store
    /// opens until `setup()` has finished it.
    ///
    /// The app first finishes or undoes any change of mode it was stopped in
    /// the middle of (`VaultStorageRecovery`). The AutoFill extension only
    /// reads the state, and treats a change underway as encrypted, so it
    /// never opens a plain store that's being converted. It can live through
    /// a conversion, so it also checks the state on every call
    /// (`GuardedPlainVaultStore`).
    @MainActor
    static let storageMode: VaultStorageRecovery.Outcome = {
        #if DEBUG
        if ScreenshotMode.isEnabled {
            return .plain
        }
        #endif
        if isAppExtension {
            return VaultStorageState.isPlain(inDirectory: vaultStorageDirectory) ? .plain : .password
        }
        do {
            return try VaultStorageRecovery(directory: vaultStorageDirectory).recoverAtLaunch()
        } catch {
            // Open no store at all: the scene shows the failure screen.
            vaultStoreLoadFailureMessage = error.localizedDescription
            return .password
        }
    }()

    /// Today's SQLite store in the App Group container, while the vault is
    /// stored in it. `nil` once encryption is on, so it's never opened then.
    ///
    /// Read and written through `vaultStore`, apart from the killphrase and
    /// search passphrase migrations, which only ever apply to this store.
    /// `releasePlainVaultStore()` lets go of it once a conversion to an
    /// encrypted vault has committed.
    @MainActor
    private(set) static var plainVaultStore: PersistedLocalVaultStore? = {
        guard storageMode == .plain else { return nil }
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

    /// Lets go of the plain store, once the store session has switched away
    /// from it, so its database closes before its files are deleted. Nothing
    /// else holds it: the rehash services look it up for each write.
    @MainActor
    static func releasePlainVaultStore() {
        plainVaultStore = nil
    }

    /// Where everything reads and writes the vault. It opens on the plain
    /// store, as the app always has, or locked once encryption is on, and
    /// can switch store (or lock) while the app runs. In the AutoFill
    /// extension the plain store is guarded, so it stops being read or
    /// written if the app converts it meanwhile.
    @MainActor
    public static let vaultStore: VaultStoreSession = {
        guard let plainVaultStore else { return .init(target: .locked) }
        guard isAppExtension else { return .init(target: .plain(plainVaultStore)) }
        return .init(target: .plain(GuardedPlainVaultStore(store: plainVaultStore, directory: vaultStorageDirectory)))
    }()

    public static let backupPasswordStore: some BackupPasswordStore =
        BackupPasswordStoreImpl(secureStorage: secureStorage, clock: clock)

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
        KillphraseRehashService(
            storeDirectory: vaultStorageDirectory,
            fileManager: fileManager,
            writer: { id, digest in
                // Looked up for each write, so the store can be released.
                // Only the plain store has phrases to rehash: converting it
                // to an encrypted vault requires there be none left.
                guard let store = await plainVaultStore else { throw VaultStoreSessionError.locked }
                try await store.applyKillphraseDigest(itemID: id, digest: digest)
            },
        )
    }

    @MainActor
    private static func makeSearchPassphraseRehashService() -> SearchPassphraseRehashService {
        SearchPassphraseRehashService(
            storeDirectory: vaultStorageDirectory,
            fileManager: fileManager,
            writer: { id, digest in
                guard let store = await plainVaultStore else { throw VaultStoreSessionError.locked }
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

    // MARK: - App Lock

    /// In the App Group's defaults, so the AutoFill and widget extensions follow the lock too.
    @MainActor
    public static let appLockSettingsStore: AppLockSettingsStore = {
        #if DEBUG
        // Marketing screenshots never show the lock, whatever the simulator has set.
        if ScreenshotMode.isEnabled {
            return ScreenshotMode.makeAppLockSettingsStore()
        }
        #endif
        return .shared()
    }()

    @MainActor
    public static let appLockService: AppLockService = .init(
        settings: appLockSettingsStore,
        authenticationService: deviceAuthenticationService,
        // None until the encrypted vault's storage can set and change the App Lock Password (VAULT-47 and VAULT-48).
        // Without one, Settings doesn't offer the password and the lock screen never asks for it.
        passwordService: nil,
        purgeSensitiveData: purgeSensitiveDataForAppLock,
        didChangeSettings: reloadWidgetTimelines,
    )

    /// Clears what a locked app shouldn't be holding: everything read from
    /// the vault, and the search, which might be a search passphrase. The
    /// feed reads the vault again once the app is unlocked.
    @MainActor
    private static func purgeSensitiveDataForAppLock() {
        // Straight away, before the task below has had a chance to run.
        vaultDataModel.purgeSensitiveData()
        Task {
            await vaultDataModel.purgeVaultContents()
        }
    }

    // MARK: - Erasing

    /// Erases every vault, back to a fresh plain store: what VAULT-34's lock
    /// screen does after too many wrong App Lock Passwords, when the user has
    /// turned that on. `setup()` finishes an erase the app was stopped in the
    /// middle of.
    @MainActor
    static let vaultEraser: VaultEraser = .init(
        directory: vaultStorageDirectory,
        session: vaultStore,
        secureStorage: secureStorage,
        attemptCounter: AppLockPasswordAttemptCounter(),
        hooks: .init(
            releasePlainStore: {
                await releasePlainVaultStore()
            },
            clearCredentialIdentities: {
                try? await vaultOtpAutofillStore.removeAll()
            },
            reloadWidgets: {
                await reloadWidgetTimelines()
            },
        ),
    )

    /// The erase `setup()` is finishing, if the app was stopped in the middle
    /// of one. The vault's views appear once it's done, so nothing reads the
    /// vault, or the keychain items it deletes, before then.
    @MainActor
    public private(set) static var finishingErase: Task<Void, Never>?

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
        vaultStoreArchives: vaultStoreArchives,
    )

    /// Vaults set aside because they couldn't be opened. Screenshot mode's store is in memory, so it has none.
    @MainActor
    static let vaultStoreArchives: any VaultStoreArchiving = {
        #if DEBUG
        if ScreenshotMode.isEnabled {
            return NoVaultStoreArchives()
        }
        #endif
        return PersistedLocalVaultStoreArchives(storageDirectory: vaultStorageDirectory)
    }()

    // MARK: - Setup

    /// Call this at app startup to wire up connections between components.
    @MainActor
    public static func setup() {
        // Finish an erase the app was stopped in the middle of. It leaves a
        // fresh, empty plain store. The vault's views wait for it.
        if storageMode == .erasing {
            finishingErase = Task {
                try? await vaultEraser.erase()
            }
        }
        // Wire up auto-backup and widget reloads to trigger when vault data
        // changes. The OTP widget reads items from the shared App Group
        // container and only refreshes when the system or this hook asks it to.
        vaultDataModel.onDataChanged = {
            autoBackupService.notifyDataChanged()
            reloadWidgetTimelines()
        }
        // Deleting all data only refreshes the widgets, so they stop showing codes that are gone. It doesn't
        // auto-backup the empty vault.
        vaultDataModel.onVaultDeleted = {
            reloadWidgetTimelines()
        }
        reloadWidgetTimelines()
        // Clear deleted content an earlier session left in the SQLite store's files, and columns a migration has
        // just dropped (MANIFESTO C6). The store scrubs after each deletion itself from then on.
        if let store = plainVaultStore {
            Task {
                await store.scrubContentLeftByEarlierSessions()
            }
        }
        // Finish a conversion to an encrypted vault that the app was stopped in the middle of: QuickType mustn't
        // keep the vault's issuers and accounts, nor the widgets its codes.
        if storageMode == .password {
            let otpAutofillStore = vaultOtpAutofillStore
            let directory = vaultStorageDirectory
            Task {
                try? await VaultStorageRecovery(directory: directory).finishClearingSystemSurfaces {
                    try? await otpAutofillStore.removeAll()
                    await reloadWidgetTimelines()
                }
            }
        }
    }

    @MainActor
    private static func reloadWidgetTimelines() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
