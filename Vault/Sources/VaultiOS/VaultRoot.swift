import Foundation
import FoundationExtensions
import SwiftSecurity
import UIKit
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

    /// Why the vault couldn't be opened, when `vaultStoreLoadFailureMessage`
    /// is set, so the failure screen can say what to do.
    @MainActor
    private(set) static var vaultStoreLoadFailureReason: VaultStoreFailureView.Reason = .storeUnreadable

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
            switch error as? VaultStorageRecovery.Failure {
            case .deviceKeyMissing:
                vaultStoreLoadFailureReason = .deviceKeyMissing
            case .vaultMissing:
                vaultStoreLoadFailureReason = .vaultMissing
            default:
                break
            }
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
            // The factory sets a store it can't open aside and starts an empty one. That one doesn't hold the vault,
            // so the password can't be set on it until the next launch opens it normally.
            let archivesBefore = vaultStoreArchives.archives().count
            let store = try PersistedLocalVaultStoreFactory(storageDirectory: vaultStorageDirectory)
                .makeVaultStoreOrThrow()
            plainVaultStoreOpenedNormally = vaultStoreArchives.archives().count == archivesBefore
            return store
        } catch {
            // Fall back to an empty in-memory store instead of crashing at
            // launch: the composition graph stays valid for every consumer
            // and the scene shows a failure screen. The failed store files
            // were archived beside the store by the factory's recovery.
            vaultStoreLoadFailureMessage = error.localizedDescription
            // It doesn't hold the vault, so it's never encrypted as if it did.
            plainVaultStoreOpenedNormally = false
            do {
                return try .inMemory()
            } catch {
                // In-memory container creation has no external failure
                // modes; if even this fails the process cannot run.
                fatalError("Unable to create fallback in-memory store: \(error)")
            }
        }
    }()

    /// Whether the plain store opened this launch without being set aside
    /// and started again empty. Converting it to an encrypted vault needs
    /// it to have: otherwise the vault is in the copy set aside.
    @MainActor
    private(set) static var plainVaultStoreOpenedNormally = true

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

    /// The plain store's backup password, in the keychain.
    static let deviceBackupPasswordStore = BackupPasswordStoreImpl(secureStorage: secureStorage, clock: clock)

    /// The plain store's backup settings, which turning encryption on moves into the real vault.
    @MainActor
    static let deviceBackupSettings = DeviceBackupSettings(
        passwordStore: deviceBackupPasswordStore,
        secureStorage: secureStorage,
        defaults: defaults,
    )

    /// The backup password, last backup, auto-backup configuration and PDF hint of whichever vault is open:
    /// device-wide for the plain store, and each encrypted vault's own. `setup()` reads them, and reads them again
    /// whenever the vault changes.
    @MainActor
    public static let openVaultBackupSettings = OpenVaultBackupSettings(
        session: vaultStore,
        device: deviceBackupSettings,
        clock: clock,
        authenticate: {
            try await deviceAuthenticationService.validateAuthentication(
                reason: "Authenticate to use the backup password.",
            )
        },
    )

    public static let killphraseKeyStore: some KillphraseKeyStore<KeyData<32>> =
        KillphraseKeyStoreImpl(secureStorage: secureStorage)

    public static let searchPassphraseKeyStore: some SearchPassphraseKeyStore<KeyData<32>> =
        SearchPassphraseKeyStoreImpl(secureStorage: secureStorage)

    /// How the vault can be opened right now: plain, with the device key, or
    /// only with the App Lock Password. Unlike `storageMode`, which is how it
    /// was at launch, this follows the password being turned on or off while
    /// the app runs, and it's what the extensions go by.
    public nonisolated static var vaultAccessMode: VaultAccessMode {
        VaultAccessMode.current(inDirectory: VaultSharedStorage.directory())
    }

    /// QuickType's identity store, which is kept empty while only the App
    /// Lock Password opens the vault: it holds codes' issuers and account
    /// names outside the app.
    public static let vaultOtpAutofillStore: some VaultOTPAutofillStore = PasswordlessOTPAutofillStore(
        base: VaultOTPAutofillStoreImpl(store: RealCredentialIdentityStore()),
        opensWithoutPassword: { vaultAccessMode.opensWithoutPassword },
    )

    /// What the AutoFill extension opens an encrypted vault with, in its own
    /// process: the App Lock Password, counted against the same attempts as
    /// the app, or the device key while the password is off. Made the first
    /// time a request finds the vault encrypted, and kept for the rest of the
    /// process.
    @MainActor
    public static func autofillVaultService() -> AutofillVaultService {
        if let service = existingAutofillVaultService {
            return service
        }
        let service = AutofillVaultService(
            directory: vaultStorageDirectory,
            session: vaultStore,
            settings: appLockSettingsStore,
            purgeVaultContents: { @MainActor in
                await vaultDataModel.purgeVaultContents()
            },
        )
        existingAutofillVaultService = service
        return service
    }

    /// The AutoFill extension's vault service, if an earlier request made
    /// one: a later request locks whatever it opened, whatever the mode now.
    @MainActor
    public private(set) static var existingAutofillVaultService: AutofillVaultService?

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
        backupPasswordStore: openVaultBackupSettings,
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
    static let backupEventLogger: some BackupEventLogger = BackupEventLoggerImpl(
        storage: openVaultBackupSettings,
        clock: clock,
    )

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
        passwordService: vaultPasswordService,
        purgeSensitiveData: purgeSensitiveDataForAppLock,
        didChangeSettings: reloadWidgetTimelines,
    )

    /// The App Lock Password, on the vault's storage: unlocking with it, and
    /// setting, changing and turning it off, and making a duress vault, in
    /// Settings. `nil` in screenshot mode, whose vault is in memory.
    @MainActor
    static let vaultPasswordService: EncryptedVaultPasswordService? = {
        #if DEBUG
        if ScreenshotMode.isEnabled {
            return nil
        }
        #endif
        let mode: VaultStorageState.Mode = switch storageMode {
        // An erase finishes before the vault shows, and leaves a fresh plain store.
        case .plain, .erasing: .plain
        case .password: .password
        case .deviceKey: .deviceKey
        }
        return EncryptedVaultPasswordService(
            directory: vaultStorageDirectory,
            mode: mode,
            session: vaultStore,
            settings: appLockSettingsStore,
            erase: {
                try await eraseVault()
            },
            archives: vaultStoreArchives,
            deviceBackupSettings: deviceBackupSettings,
            purgeVaultContents: { @MainActor in
                await vaultDataModel.purgeVaultContents()
            },
            conversionHooks: .init(
                releasePlainStore: {
                    await releasePlainVaultStore()
                },
                clearCredentialIdentities: {
                    try await vaultOtpAutofillStore.removeAll()
                },
                reloadWidgets: {
                    await reloadWidgetTimelines()
                },
            ),
            passwordHooks: .init(
                passwordDidTurnOff: {
                    try await refillSystemSurfaces()
                },
                passwordDidTurnOn: {
                    try await emptySystemSurfaces()
                },
            ),
            plainStore: {
                plainVaultStore.map { ($0, plainVaultStoreOpenedNormally) }
            },
            backgroundTime: .application,
        )
    }()

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
    /// turned that on. Go through `eraseVault()`, which also keeps
    /// `plainVaultStore` up to date.
    @MainActor
    static let vaultEraser: VaultEraser = .init(
        directory: vaultStorageDirectory,
        session: vaultStore,
        secureStorage: secureStorage,
        attemptCounter: AppLockPasswordAttemptCounter(),
        appLockSettings: appLockSettingsStore,
        defaults: defaults,
        temporaryDirectory: fileManager.temporaryDirectory,
        hooks: .init(
            releasePlainStore: {
                await releasePlainVaultStore()
            },
            clearCredentialIdentities: {
                try await vaultOtpAutofillStore.removeAll()
            },
            reloadWidgets: {
                await reloadWidgetTimelines()
            },
            forgetVaultSettings: {
                // Both read their settings at launch, before an interrupted
                // erase finishes.
                await autoBackupService.forgetConfiguration()
                await vaultDataModel.reloadLastBackupEvent()
            },
        ),
    )

    /// Erases every vault (`VaultEraser`), then reads and writes the fresh
    /// plain store it leaves, which the rehash services find here, and
    /// forgets everything held in memory from the erased vaults: their items,
    /// the backup password, and the digesters made from the keys the erase
    /// deleted.
    @MainActor
    static func eraseVault() async throws {
        plainVaultStore = try await vaultEraser.erase()
        plainVaultStoreOpenedNormally = true
        vaultPasswordService?.vaultWasErased()
        // Whether the erase started at the lock screen or not, there's no password now.
        appLockService.vaultWasErased()
        await vaultDataModel.resetAfterErase()
    }

    /// Erases and starts again, if the vault's data is missing and nothing
    /// showed an erase was meant: the failure screen offers it, and it runs
    /// only once the user confirms. Then the app starts on the fresh store, as
    /// it would have at launch. `nil` otherwise.
    @MainActor
    static let missingVault: MissingVaultViewModel? = {
        _ = storageMode
        guard vaultStoreLoadFailureReason == .vaultMissing else { return nil }
        return MissingVaultViewModel(erase: {
            try await eraseVault()
            setup()
        })
    }()

    /// Finishes an erase the app was stopped in the middle of, if there's one.
    /// `setup()` starts it, and the vault's views wait for it.
    @MainActor
    static let interruptedErase: InterruptedEraseViewModel? = storageMode == .erasing
        ? InterruptedEraseViewModel(erase: { try await eraseVault() })
        : nil

    // MARK: - Auto-Backup

    @MainActor
    static let iCloudDriveProvider: iCloudDriveProvider = .init()

    @MainActor
    public static let autoBackupService: some AutoBackupService = AutoBackupServiceImpl(
        dataModel: vaultDataModel,
        backupEventLogger: backupEventLogger,
        clock: clock,
        configurationStorage: openVaultBackupSettings,
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
        backupPDFHintStorage: openVaultBackupSettings,
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
        // fresh, empty plain store. The vault's views wait for it, and it
        // never runs twice.
        if let interruptedErase {
            Task {
                await interruptedErase.finish()
            }
        }
        // While the password is set, the vault locks as the device does,
        // whatever the delay, so its keys aren't in memory while it's locked.
        NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataWillBecomeUnavailableNotification,
            object: nil,
            queue: .main,
        ) { _ in
            MainActor.assumeIsolated {
                appLockService.deviceWillLock()
            }
        }
        // With the password off after being on, the vault is encrypted with a
        // key on this device. With the app lock off too, nothing asks the user
        // to unlock, so it opens now, as the plain store always has. Links from
        // widgets wait for it.
        appLockService.openVaultIfUnlocked()
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
        // Each vault has its own backup settings, so the Backups page, the backup password and auto-backup follow
        // whichever vault is open: reloaded, in this order, every time the store session switches vault or locks.
        // The Backups page goes first, because auto-backup waits for a backup of the previous vault to finish.
        let vaultChanges = vaultStore
        Task {
            for await _ in await vaultChanges.openVaultChanges() {
                await openVaultBackupSettings.reload()
                await vaultDataModel.openVaultDidChange()
                await autoBackupService.vaultDidChange()
            }
        }
        // Clear deleted content an earlier session left in the SQLite store's files, and columns a migration has
        // just dropped (MANIFESTO C6). The store scrubs after each deletion itself from then on.
        if let store = plainVaultStore {
            Task {
                await store.scrubContentLeftByEarlierSessions()
            }
        }
        // Finish a conversion to an encrypted vault that the app was stopped in the middle of: QuickType mustn't
        // keep the vault's issuers and accounts, nor the widgets its codes.
        if storageMode != .plain {
            // Turning encryption on moved the plain store's backup settings into the real vault. If deleting them
            // then failed, they go now: none may be left outside the encrypted vault.
            Task {
                try? await deviceBackupSettings.delete()
            }
        }
        // Bring the widgets and QuickType up to date with a change of mode the app was stopped in the middle of:
        // encryption, or the password turned on, empties QuickType; the password turned off fills it again. A step
        // that fails leaves the journal, so the next launch tries again.
        switch storageMode {
        case .password:
            let recovery = VaultStorageRecovery(directory: vaultStorageDirectory)
            Task {
                try? await recovery.finishClearingSystemSurfaces(emptySystemSurfaces)
                // And it's emptied at every launch anyway: nothing should be in it while the password is on.
                try? await vaultOtpAutofillStore.removeAll()
            }
        case .deviceKey:
            let recovery = VaultStorageRecovery(directory: vaultStorageDirectory)
            Task {
                try? await recovery.finishSyncingSystemSurfaces(refillSystemSurfaces)
            }
        case .plain, .erasing:
            break
        }
    }

    /// Reloads the widgets, which show codes again now the password is off, and fills the QuickType identity store
    /// again from the vault the device key opens. Launch recovery runs it, and turning the password off does too
    /// (`VaultPasswordChangeService.Hooks.passwordDidTurnOff`).
    ///
    /// The widgets are reloaded whatever happens to QuickType. If a fill fails, it throws, so the journal keeps the
    /// step for the next launch.
    @MainActor
    static func refillSystemSurfaces() async throws {
        defer { reloadWidgetTimelines() }
        try await fillQuickTypeWithDeviceKey()
    }

    /// Fills the QuickType identity store from the vault the device key opens, opened only to read it.
    ///
    /// Only while Vault's turned on as an AutoFill provider: otherwise the system refuses changes to the store, which
    /// holds nothing of Vault's, and turning Vault on fills it (`prepareInterfaceForExtensionConfiguration()`).
    @MainActor
    public static func fillQuickTypeWithDeviceKey() async throws {
        guard await vaultOtpAutofillStore.getState().isEnabled else { return }
        let items = try await retrieveItemsWithDeviceKey().items
        try await vaultOtpAutofillStore.syncAll(items: items)
    }

    /// The vault's items, from the vault the device key opens only to read them, locked again straight after: for
    /// QuickType, while the password is off.
    ///
    /// - Throws: `VaultUnlockError.deviceKeyNotInUse` unless the vault's stored with the device key now, or an error
    ///   opening it, such as while the device is locked after starting up.
    public nonisolated static func retrieveItemsWithDeviceKey() async throws -> VaultRetrievalResult<VaultItem> {
        try await VaultStoreSession.retrieveAndLock {
            try await VaultStoreSession.openedToShowWithDeviceKey(directory: VaultSharedStorage.directory())
        }
    }

    /// Empties the QuickType identity store, now only the password opens the vault, and reloads the widgets, which
    /// show it locked. Launch recovery runs it, and turning the password on does too
    /// (`VaultPasswordChangeService.Hooks.passwordDidTurnOn`).
    @MainActor
    static func emptySystemSurfaces() async throws {
        try await vaultOtpAutofillStore.removeAll()
        reloadWidgetTimelines()
    }

    @MainActor
    private static func reloadWidgetTimelines() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
