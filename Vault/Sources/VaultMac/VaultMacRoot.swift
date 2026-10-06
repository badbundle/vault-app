import AppKit
import Foundation
import FoundationExtensions
import SwiftSecurity
import VaultFeed
import VaultSettings

/// The composition root of the Mac app, as `VaultRoot` is of the iOS app (docs/mac-app.md).
///
/// It wires the shared services as the iOS app does, without what the Mac doesn't have: a SQLite store, widgets,
/// QuickType and Spotlight. The Mac's vault is only ever the encrypted vault file. Until the App Lock Password is set,
/// at the first launch or after an erase, the store session reads an empty store in memory, and setting the password
/// encrypts it into the vault file (`VaultEncryptionConverter`), as it converts the iOS app's SQLite store.
@MainActor
enum VaultMacRoot {
    // MARK: - Primitives

    static let defaults: Defaults = {
        #if DEBUG
        // UI tests keep their defaults with their vault.
        if let uiTestVault = UITestVaultStorage.current {
            return .init(userDefaults: uiTestVault.defaults)
        }
        #endif
        return .init(userDefaults: .standard)
    }()

    /// The App Group's defaults, for the settings the AutoFill extension reads too.
    static let sharedDefaults: Defaults = .init(userDefaults: VaultSharedStorage.userDefaults())

    static let localSettings = LocalSettings(defaults: defaults, sharedDefaults: sharedDefaults)

    static let clock: some EpochClock = EpochClockImpl()

    static let timer: some IntervalTimer = IntervalTimerImpl()

    static let fileManager: FileManager = .default

    /// Every copy Vault makes goes through here (G50).
    static let pasteboard = VaultMacPasteboard(system: NSPasteboardSystemPasteboard(), localSettings: localSettings)

    // MARK: - Stores

    /// The app's own keychain access group, as on iOS: the first in its `keychain-access-groups`. The items the
    /// AutoFill extension reads too are in the App Group, which they name.
    static let keychain: Keychain = .default

    static let secureStorage: some SecureStorage = SecureStorageImpl(keychain: keychain)

    static let vaultStorageDirectory: URL = VaultSharedStorage.directory(fileManager: fileManager)

    /// Why the vault couldn't be opened, if it couldn't. The main window shows a failure screen instead of the vault.
    private(set) static var vaultStoreLoadFailure: VaultMacStoreFailure?

    /// How the vault was stored when the app launched: `.plain` before the App Lock Password is first set, which on
    /// the Mac means there's no vault yet, or `.password`. `.erasing` if the app was stopped in the middle of an erase,
    /// which `setup()` finishes before anything opens.
    static let storageMode: VaultStorageRecovery.Outcome = {
        do {
            return try VaultStorageRecovery(directory: vaultStorageDirectory, plainStoreIsInMemory: true)
                .recoverAtLaunch()
        } catch {
            vaultStoreLoadFailure = VaultMacStoreFailure(recoveryError: error)
            return .password
        }
    }()

    /// The empty store the session reads until the App Lock Password is set, in memory: the Mac never writes a vault
    /// that isn't encrypted. `nil` once the password is set.
    private(set) static var plainVaultStore: PersistedLocalVaultStore? = storageMode == .plain ? makeEmptyStore() : nil

    /// An empty store in memory, which has no external failure modes: if it can't be made, the app can't run.
    nonisolated static func makeEmptyStore() -> PersistedLocalVaultStore {
        do {
            return try .inMemory()
        } catch {
            fatalError("Unable to create the empty in-memory store: \(error)")
        }
    }

    /// Lets go of the empty store once setting the password has encrypted it.
    static func releasePlainVaultStore() {
        plainVaultStore = nil
    }

    /// Where everything reads and writes the vault: the empty store until the password is set, then the encrypted
    /// vault, locked until it's unlocked.
    static let vaultStore: VaultStoreSession = {
        guard let plainVaultStore else { return .init(target: .locked) }
        return .init(target: .plain(plainVaultStore))
    }()

    /// The empty store's backup password and settings, which setting the password moves into the vault. There are
    /// never any: nothing can be backed up before the password is set.
    static let deviceBackupSettings = DeviceBackupSettings(
        passwordStore: BackupPasswordStoreImpl(secureStorage: secureStorage, clock: clock),
        secureStorage: secureStorage,
        defaults: defaults,
    )

    /// The open vault's backup password, last backup, auto-backup configuration and PDF hint.
    static let openVaultBackupSettings = OpenVaultBackupSettings(
        session: vaultStore,
        device: deviceBackupSettings,
        clock: clock,
        authenticate: {
            try await deviceAuthenticationService.validateAuthentication(
                reason: "Authenticate to use the backup password.",
            )
        },
    )

    static let killphraseKeyStore: some KillphraseKeyStore<KeyData<32>> =
        KillphraseKeyStoreImpl(secureStorage: secureStorage)

    static let searchPassphraseKeyStore: some SearchPassphraseKeyStore<KeyData<32>> =
        SearchPassphraseKeyStoreImpl(secureStorage: secureStorage)

    static let backupEventLogger: some BackupEventLogger = BackupEventLoggerImpl(
        storage: openVaultBackupSettings,
        clock: clock,
    )

    static let vaultDataModel: VaultDataModel = .init(
        vaultStore: vaultStore,
        vaultTagStore: vaultStore,
        vaultImporter: vaultStore,
        vaultDeleter: vaultStore,
        vaultKillphraseDeleter: vaultStore,
        // The password is always on, so the identity store that lists codes in Safari's suggestions is never written
        // (G46).
        vaultOtpAutofillStore: NoCredentialIdentities(),
        backupPasswordStore: openVaultBackupSettings,
        killphraseKeyStore: killphraseKeyStore,
        // Only an iOS SQLite store from an older version has phrases to rehash.
        killphraseRehashService: nil,
        searchPassphraseKeyStore: searchPassphraseKeyStore,
        searchPassphraseRehashService: nil,
        backupEventLogger: backupEventLogger,
    )

    // MARK: - Items

    static let vaultKeyDeriverFactory: some VaultKeyDeriverFactory = VaultKeyDeriverFactoryImpl()

    static let otpCodeTimerUpdaterFactory: some OTPCodeTimerUpdaterFactory = OTPCodeTimerUpdaterFactoryImpl(
        timer: timer,
        clock: clock,
    )

    /// Time-based codes' live codes and timers, forgotten with everything else read from the vault when it locks.
    static let totpPreviewRepository: TOTPPreviewViewRepositoryImpl = {
        let repository = TOTPPreviewViewRepositoryImpl(
            clock: clock,
            timer: timer,
            updaterFactory: otpCodeTimerUpdaterFactory,
        )
        vaultDataModel.itemCaches.append(repository)
        return repository
    }()

    /// Counter-based codes' codes, and advancing their counters.
    static let hotpPreviewRepository: HOTPPreviewViewRepositoryImpl = {
        let repository = HOTPPreviewViewRepositoryImpl(timer: timer, store: vaultDataModel)
        vaultDataModel.itemCaches.append(repository)
        return repository
    }()

    /// What the main window shows.
    static let feedModel = VaultMacFeedModel(dataModel: vaultDataModel)

    /// The text to copy for a code, from whichever repository shows it.
    static let vaultItemCopyHandler = GenericVaultItemCopyActionHandler(childHandlers: [
        totpPreviewRepository,
        hotpPreviewRepository,
    ])

    // MARK: - App Lock

    static let deviceAuthenticationService: DeviceAuthenticationService = {
        #if DEBUG
        if let policy = VaultMacUITestVault.authenticationPolicy {
            return .init(policy: policy)
        }
        #endif
        return .init(policy: .default)
    }()

    /// In the App Group's defaults, so the AutoFill extension follows the lock too.
    static let appLockSettingsStore: AppLockSettingsStore = {
        let settings = AppLockSettingsStore.shared()
        #if DEBUG
        if let delay = VaultMacUITestVault.appLockDelay {
            settings.delay = delay
        }
        #endif
        return settings
    }()

    static let appLockService: AppLockService = .init(
        settings: appLockSettingsStore,
        authenticationService: deviceAuthenticationService,
        passwordService: vaultPasswordService,
        purgeSensitiveData: {
            // Straight away, then everything read from the vault. No item's page is open when it's unlocked again.
            feedModel.selectedItemID = nil
            vaultDataModel.purgeSensitiveData()
            Task { await vaultDataModel.purgeVaultContents() }
        },
    )

    /// The App Lock Password on the vault's storage: setting it at the first launch, unlocking with it, changing it,
    /// and making a duress vault. The Mac never turns it off.
    static let vaultPasswordService: EncryptedVaultPasswordService = {
        let mode: VaultStorageState.Mode = switch storageMode {
        case .plain, .erasing: .plain
        case .password: .password
        // The Mac never turns the password off. If a vault's file says it is, the lock asks for nothing more than
        // device authentication, as on iOS, and Settings offers to set the password again.
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
            archives: NoVaultStoreArchives(),
            deviceBackupSettings: deviceBackupSettings,
            purgeVaultContents: { @MainActor in
                await vaultDataModel.purgeVaultContents()
            },
            conversionHooks: .init(
                releasePlainStore: {
                    await releasePlainVaultStore()
                },
                clearCredentialIdentities: {},
                reloadWidgets: {},
            ),
            passwordHooks: .init(
                passwordDidTurnOff: {},
                passwordDidTurnOn: {},
            ),
            plainStore: {
                // It never fails to open: it's in memory.
                plainVaultStore.map { ($0, true) }
            },
            backgroundTime: .macProcess,
            calibration: keyDerivationCalibration,
        )
    }()

    /// The key derivation's parameters for a password set here, or `nil` to calibrate them on this Mac as it's set.
    private static let keyDerivationCalibration: AppLockKeyDerivationCalibration? = {
        #if DEBUG
        return VaultMacUITestVault.keyDerivationCalibration
        #else
        return nil
        #endif
    }()

    // MARK: - Erasing

    /// Erases every vault, leaving a fresh, empty store in memory: after too many wrong App Lock Passwords, when the
    /// user has turned that on, and Delete All Data. Go through `eraseVault()`.
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
            clearCredentialIdentities: {},
            reloadWidgets: {},
            forgetVaultSettings: {
                // Both read their settings at launch, before an interrupted erase finishes.
                await autoBackupService.forgetConfiguration()
                await vaultDataModel.reloadLastBackupEvent()
            },
        ),
        makePlainStore: { makeEmptyStore() },
    )

    /// Which Help page is open.
    static let help = VaultMacHelpModel()

    // MARK: - Backups

    static let encryptedVaultDecoder: some EncryptedVaultDecoder<KeyData<32>> = EncryptedVaultDecoderImpl()

    /// The folder the user chose for Auto-Backup, such as one in iCloud Drive, kept with a security-scoped bookmark.
    static let backupFolderProvider: iCloudDriveProvider = .init()

    /// Writes, keeps and cleans up backups in that folder, as on iOS (G62).
    static let autoBackupService: some AutoBackupService = AutoBackupServiceImpl(
        dataModel: vaultDataModel,
        backupEventLogger: backupEventLogger,
        clock: clock,
        configurationStorage: openVaultBackupSettings,
        providers: [backupFolderProvider],
    )

    /// Erases every vault (`VaultEraser`), then reads and writes the fresh, empty store it leaves, and forgets
    /// everything held in memory from the erased vaults. The app goes back to its first launch: the password has to be
    /// set again before anything can be added.
    static func eraseVault() async throws {
        plainVaultStore = try await vaultEraser.erase()
        vaultPasswordService.vaultWasErased()
        appLockService.vaultWasErased()
        await vaultDataModel.resetAfterErase()
    }

    /// Erases and starts again, if the vault's data is missing and nothing showed an erase was meant, once the user
    /// confirms on the failure screen. `nil` otherwise.
    static let missingVault: MissingVaultViewModel? = {
        _ = storageMode
        guard vaultStoreLoadFailure == .vaultMissing else { return nil }
        return MissingVaultViewModel(erase: {
            try await eraseVault()
            vaultStoreLoadFailure = nil
            setup()
        })
    }()

    /// Finishes an erase the app was stopped in the middle of, if there's one. `setup()` starts it, and the vault's
    /// views wait for it.
    static let interruptedErase: InterruptedEraseViewModel? = storageMode == .erasing
        ? InterruptedEraseViewModel(erase: { try await eraseVault() })
        : nil

    // MARK: - Setup

    /// The lock triggers, kept for as long as the app runs.
    private static var lockTriggers: VaultMacLockTriggers?
    private static var windowPrivacy: VaultMacWindowPrivacy?

    /// Wires the app together at launch.
    static func setup() {
        if let interruptedErase {
            Task {
                await interruptedErase.finish()
            }
        }
        lockTriggers = VaultMacLockTriggers(appLock: appLockService)
        let windowPrivacy = VaultMacWindowPrivacy(localSettings: localSettings, appLock: appLockService)
        windowPrivacy.start(windows: NSApplication.shared.windows)
        self.windowPrivacy = windowPrivacy
        // Each vault has its own backup settings, read again whenever the session switches vault or locks.
        // A change to the vault backs it up, if Auto-Backup is on.
        vaultDataModel.onDataChanged = {
            autoBackupService.notifyDataChanged()
        }
        // The Backups page goes first, because auto-backup waits for a backup of the previous vault to finish.
        let vaultChanges = vaultStore
        Task {
            for await _ in await vaultChanges.openVaultChanges() {
                await openVaultBackupSettings.reload()
                await vaultDataModel.openVaultDidChange()
                await autoBackupService.vaultDidChange()
            }
        }
    }
}

/// Why the Mac app couldn't open its vault at launch.
enum VaultMacStoreFailure: Equatable {
    /// The vault's files couldn't be read or made sense of.
    case storeUnreadable
    /// The vault's file is missing, and nothing shows an erase was meant.
    case vaultMissing
    /// The vault is encrypted with a key on this Mac, which is missing.
    case deviceKeyMissing

    init(recoveryError error: any Error) {
        switch error as? VaultStorageRecovery.Failure {
        case .vaultMissing: self = .vaultMissing
        case .deviceKeyMissing: self = .deviceKeyMissing
        default: self = .storeUnreadable
        }
    }
}

extension VaultBackgroundTime {
    /// Keeps macOS from ending the app abruptly while the storage changes. Mac apps aren't suspended, but macOS can
    /// end one that has said it can be (sudden termination), as at log out. Launch recovery finishes or undoes a change
    /// that was stopped anyway, from its journal.
    static let macProcess = VaultBackgroundTime { @MainActor in
        ProcessInfo.processInfo.disableSuddenTermination()
        return { @MainActor in
            ProcessInfo.processInfo.enableSuddenTermination()
        }
    }
}
