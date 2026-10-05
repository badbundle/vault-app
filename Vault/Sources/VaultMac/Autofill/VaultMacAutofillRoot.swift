import Foundation
import FoundationExtensions
import SwiftSecurity
import VaultCore
import VaultFeed
import VaultSettings

/// What the AutoFill extension opens the vault with, in its own process: only what it needs to unlock the vault with
/// the App Lock Password and list its codes. It never touches `VaultMacRoot`, which recovers and converts the vault at
/// the app's launch: the extension only ever reads the vault as the app left it.
@MainActor
final class VaultMacAutofillRoot {
    static let shared = VaultMacAutofillRoot()

    let directory = VaultSharedStorage.directory(fileManager: .default)
    /// The App Group's defaults: the settings the app shares with the extension, such as Hide While Recording.
    let sharedDefaults: Defaults
    let localSettings: LocalSettings
    let appLockSettings = AppLockSettingsStore.shared()
    let authentication = DeviceAuthenticationService(policy: .default)
    let clock: some EpochClock = EpochClockImpl()
    let timer: some IntervalTimer = IntervalTimerImpl()
    /// Locked until the App Lock Password opens it.
    let session = VaultStoreSession(target: .locked)
    let dataModel: VaultDataModel
    let totpPreviews: TOTPPreviewViewRepositoryImpl
    let hotpPreviews: HOTPPreviewViewRepositoryImpl
    /// Opens the vault with the App Lock Password, counted against the same attempts as the app, and never the last
    /// one before the vault would be erased (G20).
    let vaultService: AutofillVaultService

    private init() {
        let defaults = Defaults(userDefaults: UserDefaults(suiteName: VaultSharedStorage.appGroupID) ?? .standard)
        sharedDefaults = defaults
        localSettings = LocalSettings(defaults: defaults, sharedDefaults: defaults)
        // The phrase keyrings are never read here: the extension's search doesn't check killphrases or find hidden
        // items (G2, G47), as `VaultDataModel.setup()` is never called.
        let secureStorage = SecureStorageImpl(keychain: .default)
        let dataModel = VaultDataModel(
            vaultStore: session,
            vaultTagStore: session,
            vaultImporter: session,
            vaultDeleter: session,
            vaultKillphraseDeleter: session,
            vaultOtpAutofillStore: NoCredentialIdentities(),
            backupPasswordStore: BackupPasswordStoreImpl(secureStorage: secureStorage, clock: clock),
            killphraseKeyStore: KillphraseKeyStoreImpl(secureStorage: secureStorage),
            killphraseRehashService: nil,
            searchPassphraseKeyStore: SearchPassphraseKeyStoreImpl(secureStorage: secureStorage),
            searchPassphraseRehashService: nil,
            backupEventLogger: BackupEventLoggerImpl(storage: defaults, clock: clock),
        )
        self.dataModel = dataModel
        totpPreviews = TOTPPreviewViewRepositoryImpl(
            clock: clock,
            timer: timer,
            updaterFactory: OTPCodeTimerUpdaterFactoryImpl(timer: timer, clock: clock),
        )
        hotpPreviews = HOTPPreviewViewRepositoryImpl(timer: timer, store: dataModel)
        dataModel.itemCaches.append(totpPreviews)
        dataModel.itemCaches.append(hotpPreviews)
        vaultService = AutofillVaultService(
            directory: directory,
            session: session,
            settings: appLockSettings,
            purgeVaultContents: { @MainActor in
                await dataModel.purgeVaultContents()
            },
        )
    }

    /// How the vault can be opened now, read afresh each time: on the Mac, only with the App Lock Password, once the
    /// app's first launch has set it.
    nonisolated static func accessMode() -> VaultAccessMode {
        VaultAccessMode.current(inDirectory: VaultSharedStorage.directory(fileManager: .default))
    }

    /// The codes' previews, from the extension's own repositories.
    var previews: VaultMacItemPreviews {
        VaultMacItemPreviews(
            totp: { [totpPreviews] in totpPreviews.previewViewModel(metadata: $0, code: $1) },
            hotp: { [hotpPreviews] in hotpPreviews.previewViewModel(metadata: $0, code: $1) },
            timer: { [totpPreviews] in totpPreviews.timerPeriodState(period: $0) },
            incrementer: { _, _ in nil },
        )
    }
}
