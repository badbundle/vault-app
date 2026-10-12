import AppKit
import Foundation
import FoundationExtensions
import SwiftSecurity
import VaultFeed
import VaultSettings
import WidgetKit

/// The composition root of the Mac app, as `VaultRoot` is of the iOS app (docs/mac-app.md).
///
/// It wires the shared services as the iOS app does, without what the Mac doesn't have: a SQLite store, QuickType and
/// Spotlight. Its widgets never read the vault: it hands them codes while it's unlocked (`VaultMacWidgetCodes`). The
/// Mac's vault is only ever the encrypted vault file. Until the App Lock Password is set,
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

    /// The app's own keychain access group, `…vault.private`: the first in its `keychain-access-groups`, and the only
    /// one its own items are read from or written to, so nothing in the App Group, which the AutoFill extension shares,
    /// is ever taken for one of them. The items the extension reads too name the App Group themselves.
    static let keychain = Keychain(accessGroup: .keychainGroup(
        teamID: "442P244AFS",
        nameID: "com.badbundle.vault.private",
    ))

    static let secureStorage: some SecureStorage = SecureStorageImpl(keychain: keychain)

    static let vaultStorageDirectory: URL = VaultSharedStorage.directory(fileManager: fileManager)

    /// Keep Out of Time Machine, in Settings: whether the App Group's container, with the vault file, is left out of
    /// Time Machine's backups. On unless the user turns it off, which is kept with the app lock's device settings.
    static let vaultBackupExclusion = VaultStorageBackupExclusion(
        directory: vaultStorageDirectory,
        settings: appLockSettingsStore,
    )

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

    /// The killphrase and search passphrase keyrings in the keychain: the empty store's, which setting the password
    /// moves into the vault, and those vaults made before they kept their own used. The Mac has no device key mode.
    static let devicePhraseKeyrings = DevicePhraseKeyrings(secureStorage: secureStorage)

    /// The open vault's killphrase and search passphrase keyrings, which an encrypted vault keeps in its payload, so
    /// they move with the vault file, to another Mac with Migration Assistant or a Time Machine restore.
    static let openVaultPhraseKeyrings = OpenVaultPhraseKeyrings(session: vaultStore, device: devicePhraseKeyrings)

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
        killphraseKeyStore: openVaultPhraseKeyrings.killphraseKeys,
        // Only an iOS SQLite store from an older version has phrases to rehash.
        killphraseRehashService: nil,
        searchPassphraseKeyStore: openVaultPhraseKeyrings.searchPassphraseKeys,
        searchPassphraseRehashService: nil,
        backupEventLogger: backupEventLogger,
        // The app moves a backup key to a stronger derivation once it's loaded. The AutoFill extension, which has its
        // own data model, never does.
        backupPasswordUpgrader: BackupPasswordUpgrader(keyDeriverFactory: vaultKeyDeriverFactory),
        phraseKeyringsCleanup: openVaultPhraseKeyrings,
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

    /// In the App Group's defaults, so the AutoFill extension follows the lock too, with erasing after failed passwords
    /// and the Require Unlock delay in the keychain item they share, where only Vault can change them.
    static let appLockSettingsStore: AppLockSettingsStore = {
        let settings = AppLockSettingsStore.shared()
        #if DEBUG
        if let delay = VaultMacUITestVault.appLockDelay {
            do {
                try settings.setDelay(delay)
            } catch {
                fatalError("Unable to set the UI test's Require Unlock: \(error)")
            }
        }
        #endif
        return settings
    }()

    static let appLockService: AppLockService = .init(
        settings: appLockSettingsStore,
        authenticationService: deviceAuthenticationService,
        passwordService: vaultPasswordService,
        purgeSensitiveData: {
            // The widgets' codes first, before anything else can run.
            widgetCodes.withdraw()
            // Straight away, then everything read from the vault. No item's page or tag is open when it's unlocked
            // again, which could be into another vault, so nothing shows which was open before (C2).
            feedModel.selectedItemID = nil
            feedModel.sidebarSelection = .items
            // What Vault copied doesn't outlast the vault it came from, nor does a code a widget copied.
            widgetCopies.takeOver()
            pasteboard.clearNow()
            // Nor does a save, open or print panel showing a backup, or the folder it was choosing.
            if NSApplication.shared.modalWindow != nil {
                NSApplication.shared.abortModal()
            }
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
            devicePhraseKeyrings: devicePhraseKeyrings,
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
    /// user has turned that on, and Erase and Start Again on the failure screen. Go through `eraseVault()`. (Delete All
    /// Data empties every vault instead, through `VaultDataModel.deleteVault()`, and keeps the password.)
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

    // MARK: - Widgets

    /// The codes the widgets may show, handed over while the vault's unlocked and taken back as it locks (G98).
    static let widgetCodes = VaultMacWidgetCodes(
        store: WidgetCodeHandoffStore(),
        isUnlocked: { !appLockService.isLocked },
        retrieveItems: { [vaultStore] in
            // Only an unlocked encrypted vault's: before the App Lock Password is first set, there's no vault.
            guard case .encrypted = await vaultStore.openVault else { return nil }
            return try await vaultStore.retrieve(query: VaultStoreQuery()).items
        },
        reloadWidgets: {
            WidgetCenter.shared.reloadAllTimelines()
        },
    )

    /// Clears the codes widgets copy, as Vault's own copies are cleared (G87).
    static let widgetCopies = VaultMacWidgetCopies(notes: WidgetCopiedCodeStore(), pasteboard: pasteboard)

    /// Hands the widgets codes, or takes them back, whenever the app locks or unlocks.
    private static func updateWidgetCodesWhenTheLockChanges() {
        _ = withObservationTracking {
            appLockService.isLocked
        } onChange: {
            Task { @MainActor in
                updateWidgetCodesWhenTheLockChanges()
            }
        }
        widgetCodes.update()
    }

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
        feedModel.selectedItemID = nil
        feedModel.sidebarSelection = .items
        // AppKit's own memory of the folders its panels last showed, which could be where the backups are.
        for key in defaultsKeysOfOpenAndSavePanels() {
            UserDefaults.standard.removeObject(forKey: key)
        }
        plainVaultStore = try await vaultEraser.erase()
        vaultPasswordService.vaultWasErased()
        appLockService.vaultWasErased()
        await vaultDataModel.resetAfterErase()
    }

    /// The keys AppKit keeps for the Open and Save panels, such as the last folder each showed.
    static func defaultsKeysOfOpenAndSavePanels(in defaults: UserDefaults = .standard) -> [String] {
        defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("NSNav") }
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
        // At every launch, so the vault stays out of Time Machine unless the user lets it in, whenever it was made.
        vaultBackupExclusion.apply()
        // The keychain items an earlier version kept in the App Group's access group move to the one only the app and
        // its AutoFill extension have, before an erase the app was stopped in the middle of finishes, which deletes
        // them wherever they are.
        let interruptedErase = interruptedErase
        Task {
            await SharedKeychainItems.moveFromTheAppGroup()
            await interruptedErase?.finish()
        }
        // Whatever an earlier run left, which stopped without locking if there's any. Every launch starts locked.
        widgetCodes.withdrawLeftovers()
        widgetCopies.start()
        lockTriggers = VaultMacLockTriggers(appLock: appLockService, authentication: deviceAuthenticationService)
        let windowPrivacy = VaultMacWindowPrivacy(localSettings: localSettings, appLock: appLockService)
        windowPrivacy.start(windows: NSApplication.shared.windows)
        self.windowPrivacy = windowPrivacy
        // Each vault has its own backup settings, read again whenever the session switches vault or locks.
        // A change to the vault backs it up, if Auto-Backup is on.
        vaultDataModel.onDataChanged = {
            autoBackupService.notifyDataChanged()
            widgetCodes.update()
        }
        vaultDataModel.onVaultDeleted = {
            widgetCodes.update()
        }
        updateWidgetCodesWhenTheLockChanges()
        // The Backups page goes first, because auto-backup waits for a backup of the previous vault to finish.
        let vaultChanges = vaultStore
        Task {
            for await _ in await vaultChanges.openVaultChanges() {
                await openVaultBackupSettings.reload()
                await vaultDataModel.openVaultDidChange()
                await autoBackupService.vaultDidChange()
                widgetCodes.update()
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
