// swiftlint:disable:next no_preconcurrency
@preconcurrency import AuthenticationServices
import Combine
import Foundation
import FoundationExtensions
import VaultKeygen

/// Provides access to the vault data layer for the UI layer.
///
/// Uses the underlying data stores and provides observations to the underlying data when it changes.
/// This should be the primary way to interact with the vault data layer (and its underlying stores),
/// to ensure that we have a consistent view of the available data at all times, regardless of the view.
///
/// This is isolated to the main actor for the purposes of UI interop.
@MainActor
@Observable
public final class VaultDataModel {
    public enum State {
        case base, loaded, loading
    }

    // MARK: Searching Items

    public var itemsSearchQuery: String = ""
    public var itemsFilteringByTags: Set<Identifier<VaultItemTag>> = []
    public var itemSearchHash: Int {
        var hasher = Hasher()
        hasher.combine(itemsSearchQuery)
        hasher.combine(itemsFilteringByTags)
        return hasher.finalize()
    }

    public var isSearching: Bool {
        itemsSanitizedQuery != nil
    }

    public var feedTitle: String {
        if isSearching {
            localized(key: "feedViewModel.searching.title.\(items.count)")
        } else {
            localized(key: "feedViewModel.list.title")
        }
    }

    /// Pluralized count of the items the feed is currently showing.
    ///
    /// Counts only what the feed displays: items hidden behind a search
    /// passphrase are excluded by the store query and must stay that way, so
    /// this never reveals that hidden items exist.
    public var itemsCountDescription: String {
        localized(key: "feedViewModel.searching.title.\(items.count)")
    }

    /// Pluralized count of the items matching the search query.
    ///
    /// The same count as `itemsCountDescription`, worded as search results,
    /// so it carries the same guarantee: items that stay hidden behind a
    /// search passphrase are never counted.
    public var itemsMatchCountDescription: String {
        localized(key: "feedViewModel.searching.matches.\(items.count)")
    }

    public var filteringByTagsDescription: String {
        localized(key: "feed.searching.filteringByTags.\(itemsFilteringByTags.count)")
    }

    private var itemsSanitizedQuery: String? {
        let trimmed = itemsSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isNotEmpty else { return nil }
        return trimmed
    }

    // MARK: Items

    public var items = [VaultItem]()
    /// Whether the feed shows any item with no search or tag filter. An item that only a search shows, such as one
    /// behind a search passphrase, doesn't count, so a vault that holds only those looks empty here, as it does in the
    /// feed.
    ///
    /// `reloadItems()` updates it while there's no search or tag filter, and `reloadHasVisibleItems()` whatever there
    /// is.
    public private(set) var hasVisibleItems = false
    public private(set) var itemErrors = [VaultRetrievalResult<VaultItem>.Error]()
    public private(set) var itemsState: State = .base
    public private(set) var itemsRetrievalError: PresentationError?
    public var itemCaches: [any VaultItemCache]

    // MARK: Tags

    public var allTags = [VaultItemTag]()
    public private(set) var allTagsState: State = .base
    public private(set) var allTagsRetrievalError: PresentationError?

    // MARK: - Backup Password

    public enum BackupPasswordState: Sendable, Equatable {
        case notFetched
        case notCreated
        case fetched(DerivedEncryptionKey)
        case error(PresentationError)

        public var fetchedPassword: DerivedEncryptionKey? {
            switch self {
            case let .fetched(password): password
            default: nil
            }
        }

        public var isRetryable: Bool {
            switch self {
            case .error, .notFetched: true
            case .notCreated, .fetched: false
            }
        }

        public var isError: Bool {
            switch self {
            case .error: true
            default: false
            }
        }
    }

    public private(set) var backupPassword: BackupPasswordState = .notFetched
    public private(set) var backupPasswordLoadingState: LoadingState = .notLoading

    public enum BackupPasswordStatus: Sendable, Equatable {
        /// Not loaded yet, or the store couldn't be read and nothing was known before.
        case unknown
        case notSet
        case set(BackupPasswordMetadata)

        public var isSet: Bool {
            switch self {
            case .set: true
            case .unknown, .notSet: false
            }
        }
    }

    /// Whether a backup password is set, for surfaces that aren't behind device authentication.
    ///
    /// Unlike `backupPassword`, loading this never loads the key itself or asks the user to
    /// authenticate. If the store can't answer, it keeps what was already known (`.unknown` at
    /// first), so a status the user has seen doesn't disappear. Setting or loading the password
    /// also brings it up to date.
    public private(set) var backupPasswordStatus: BackupPasswordStatus = .unknown

    /// Made from the open vault's killphrase keyring (`OpenVaultPhraseKeyrings`). Cached here so the killphrase
    /// match and write paths don't read the keys on every keystroke. Loaded on `setup()`, and again whenever the open
    /// vault changes (`openVaultDidChange()`), as each vault has its own keys. `nil` while no vault is open, or its
    /// keys couldn't be read.
    public private(set) var killphraseDigester: KillphraseDigester?

    /// Cached search-passphrase HMAC digester. Same lifecycle as
    /// `killphraseDigester`, used for both the live search predicate
    /// (passphrase-protected item match) and the editor write path.
    public private(set) var searchPassphraseDigester: SearchPassphraseDigester?

    // MARK: - Backup Events

    /// The last time the user's vault was backed up.
    /// This will always be kept up-to-date.
    public private(set) var lastBackupEvent: VaultBackupEvent?

    /// An up-to-date hash of the current user data payload.
    /// This is so it can be compared to the last backup event to see if we have any changes.
    public private(set) var currentPayloadHash: Digest<VaultApplicationPayload>.SHA256?

    /// Callback invoked when vault data changes (items or tags added, updated, deleted, or imported).
    /// Use this to trigger auto-backup or other side effects.
    public var onDataChanged: (() -> Void)?

    /// Callback invoked once every item and tag has been deleted.
    ///
    /// Use this to clear anything that shows vault data outside the app, such as widgets. `onDataChanged` isn't called
    /// for a deletion, so an empty vault isn't auto-backed up.
    public var onVaultDeleted: (() -> Void)?

    // MARK: - Init

    private let vaultStore: any VaultStore
    private let vaultTagStore: any VaultTagStore
    private let vaultImporter: any VaultStoreImporter
    private let vaultDeleter: any VaultStoreDeleter
    private let vaultKillphraseDeleter: any VaultStoreKillphraseDeleter
    private let vaultOtpAutofillStore: any VaultOTPAutofillStore
    private let backupPasswordStore: any BackupPasswordStore
    private let killphraseKeyStore: any KillphraseKeyStore<KeyData<32>>
    private let killphraseRehashService: KillphraseRehashService?
    private let searchPassphraseKeyStore: any SearchPassphraseKeyStore<KeyData<32>>
    private let searchPassphraseRehashService: SearchPassphraseRehashService?
    /// Deletes the keychain's keyrings no vault needs once Delete All Data has destroyed the others. `nil` where
    /// nothing deletes the vault.
    private let phraseKeyringsCleanup: (any PhraseKeyringsCleanup)?
    private let backupEventLogger: any BackupEventLogger
    /// Moves a loaded backup key to a stronger derivation, or `nil` where that mustn't happen: in an extension.
    private let backupPasswordUpgrader: (any BackupPasswordUpgrading)?
    private var observationBag = Set<AnyCancellable>()
    /// Counts `purgeVaultContents()` calls. A reload that started before the
    /// latest one is out of date by the time it finishes, so it's dropped.
    @ObservationIgnored private var contentsGeneration = 0
    /// Counts `openVaultDidChange()` calls, so what one reads for a vault that's
    /// no longer open is dropped.
    @ObservationIgnored private var openVaultChanges = 0
    /// Counts the backup passwords set or removed, so an upgraded key never replaces one set since the key it came
    /// from was loaded.
    @ObservationIgnored private var backupPasswordWrites = 0
    /// The backup key being moved to a stronger derivation, if one is.
    @ObservationIgnored private var backupPasswordUpgrade: Task<Void, Never>?

    public init(
        vaultStore: any VaultStore,
        vaultTagStore: any VaultTagStore,
        vaultImporter: any VaultStoreImporter,
        vaultDeleter: any VaultStoreDeleter,
        vaultKillphraseDeleter: any VaultStoreKillphraseDeleter,
        vaultOtpAutofillStore: any VaultOTPAutofillStore,
        backupPasswordStore: any BackupPasswordStore,
        killphraseKeyStore: any KillphraseKeyStore<KeyData<32>>,
        killphraseRehashService: KillphraseRehashService?,
        searchPassphraseKeyStore: any SearchPassphraseKeyStore<KeyData<32>>,
        searchPassphraseRehashService: SearchPassphraseRehashService?,
        backupEventLogger: any BackupEventLogger,
        itemCaches: [any VaultItemCache] = [],
        backupPasswordUpgrader: (any BackupPasswordUpgrading)? = nil,
        phraseKeyringsCleanup: (any PhraseKeyringsCleanup)? = nil,
    ) {
        self.vaultStore = vaultStore
        self.vaultTagStore = vaultTagStore
        self.vaultImporter = vaultImporter
        self.vaultDeleter = vaultDeleter
        self.vaultKillphraseDeleter = vaultKillphraseDeleter
        self.vaultOtpAutofillStore = vaultOtpAutofillStore
        self.backupPasswordStore = backupPasswordStore
        self.killphraseKeyStore = killphraseKeyStore
        self.killphraseRehashService = killphraseRehashService
        self.searchPassphraseKeyStore = searchPassphraseKeyStore
        self.searchPassphraseRehashService = searchPassphraseRehashService
        self.backupEventLogger = backupEventLogger
        self.itemCaches = itemCaches
        self.backupPasswordUpgrader = backupPasswordUpgrader
        self.phraseKeyringsCleanup = phraseKeyringsCleanup

        monitorBackupEvents()
    }

    /// Initial setup to ensure the model is in a good state.
    public func setup() async {
        await loadKillphraseDigester()
        await loadSearchPassphraseDigester()
        await updateCurrentPayloadHash()
    }

    /// Loads or generates the open vault's killphrase HMAC key and caches a
    /// digester while that vault is open. Safe to call multiple times —
    /// no-op if digester is already built. One made for a vault that's no
    /// longer open is dropped (`openVaultDidChange()`).
    public func loadKillphraseDigester() async {
        if killphraseDigester != nil {
            return
        }
        let change = openVaultChanges
        do {
            let digester = try await makeKillphraseDigester()
            guard change == openVaultChanges else { return }
            killphraseDigester = digester
            // Phase B of the V1 → V2 killphrase migration. Idempotent;
            // does nothing if there are no pending entries. Best-effort —
            // failure here must not block normal startup.
            await killphraseRehashService?.run(using: digester)
        } catch {
            // Silent failure: we don't want to surface an alert here. The
            // killphrase deleter will simply remain a no-op until the keys
            // are read again, when the open vault next changes or at the next
            // launch. No telemetry per MANIFESTO C3.
        }
    }

    /// Loads or generates the open vault's search-passphrase HMAC key and
    /// caches a digester while that vault is open. Same shape as
    /// `loadKillphraseDigester`; failure leaves passphrase matching disabled
    /// until the keys are read again.
    public func loadSearchPassphraseDigester() async {
        if searchPassphraseDigester != nil {
            return
        }
        let change = openVaultChanges
        do {
            let digester = try await makeSearchPassphraseDigester()
            guard change == openVaultChanges else { return }
            searchPassphraseDigester = digester
            // Phase B of the V2 → V3 search-passphrase migration.
            await searchPassphraseRehashService?.run(using: digester)
        } catch {
            // Silent failure per MANIFESTO C3.
        }
    }

    /// A digester that makes digests with this device's own key, and matches with every key on the keyring. The keys
    /// from backups are only needed to match what was restored, so failing to read them doesn't stop the device's own
    /// killphrases working.
    private func makeKillphraseDigester() async throws -> KillphraseDigester {
        let key = try await killphraseKeyStore.loadOrCreate()
        let keysFromBackups = (try? await killphraseKeyStore.loadKeysFromBackups()) ?? []
        return KillphraseDigester(key: key, keysFromBackups: keysFromBackups)
    }

    /// As `makeKillphraseDigester()`, for search passphrases.
    private func makeSearchPassphraseDigester() async throws -> SearchPassphraseDigester {
        let key = try await searchPassphraseKeyStore.loadOrCreate()
        let keysFromBackups = (try? await searchPassphraseKeyStore.loadKeysFromBackups()) ?? []
        return SearchPassphraseDigester(key: key, keysFromBackups: keysFromBackups)
    }

    /// Forgets everything held from the vaults an erase has just removed (`VaultEraser`): what `purgeVaultContents()`
    /// forgets, the last backup event, and the killphrase and search passphrase digesters, whose keys the erase
    /// deleted, which `purgeSensitiveData()` keeps. Then it sets up again with the fresh vault, and new keys.
    public func resetAfterErase() async {
        await purgeVaultContents()
        killphraseDigester = nil
        searchPassphraseDigester = nil
        reloadLastBackupEvent()
        await setup()
        await reloadData()
    }

    /// Reads the last backup event again, for when it's been cleared underneath the model, by an erase
    /// (`VaultEraser`).
    public func reloadLastBackupEvent() {
        lastBackupEvent = backupEventLogger.lastBackupEvent()
    }

    private func monitorBackupEvents() {
        lastBackupEvent = backupEventLogger.lastBackupEvent()
        backupEventLogger.loggedEventPublisher.sink { [weak self] newEvent in
            self?.lastBackupEvent = newEvent
        }.store(in: &observationBag)
    }

    /// Updates the current payload hash in the background.
    /// Dropped if another vault opens while it's computed: it'd be the previous vault's hash, and auto-backup would
    /// compare the next vault's backups against it (`openVaultDidChange()`).
    private func updateCurrentPayloadHash() async {
        let change = openVaultChanges
        let hash = try? await computeVaultHash()
        guard change == openVaultChanges else { return }
        currentPayloadHash = hash
    }

    private nonisolated func computeVaultHash() async throws -> Digest<VaultApplicationPayload>.SHA256 {
        let exported = try await vaultStore.exportVault(userDescription: "")
        return try Digest<VaultApplicationPayload>.SHA256.makeHash(exported)
    }
}

// MARK: - Helpers

extension VaultDataModel {
    private func invalidateCaches(itemID: Identifier<VaultItem>) async {
        for itemCache in itemCaches {
            await itemCache.vaultItemCacheClear(forVaultItemWithID: itemID)
        }
    }

    public func code(id: Identifier<VaultItem>) -> VaultItem? {
        items.first(where: { $0.id == id })
    }

    public func toggleFiltering(tag: Identifier<VaultItemTag>) {
        if itemsFilteringByTags.contains(tag) {
            itemsFilteringByTags.remove(tag)
        } else {
            itemsFilteringByTags.insert(tag)
        }
    }

    /// Ensures that any sensitive data is removed from memory.
    public func purgeSensitiveData() {
        backupPassword = .notFetched
        backupPasswordLoadingState = .notLoading
        // The digesters are intentionally NOT cleared here: the plain store
        // stays open behind the app lock, and clearing them would break
        // killphrase deletion until they're read again. They follow the open
        // vault instead, so an encrypted vault's go when it locks
        // (`openVaultDidChange()`).
    }

    /// Forgets everything read from the vault, for when the app locks: the
    /// items and tags, what the item caches hold, and the search and tag
    /// filter, which might be a search passphrase and what it revealed.
    /// Also everything `purgeSensitiveData()` forgets.
    ///
    /// `reloadData()` reads it all again once the app is unlocked. A reload
    /// that's still underway when this is called finishes without putting
    /// anything back.
    public func purgeVaultContents() async {
        purgeSensitiveData()
        contentsGeneration += 1
        itemsSearchQuery = ""
        itemsFilteringByTags = []
        items = []
        itemErrors = []
        hasVisibleItems = false
        itemsState = .base
        itemsRetrievalError = nil
        allTags = []
        allTagsState = .base
        allTagsRetrievalError = nil
        for itemCache in itemCaches {
            await itemCache.vaultItemCacheClearAll()
        }
    }
}

// MARK: - Open Vault

extension VaultDataModel {
    /// Follows the vault that's open now, once its backup settings have
    /// reloaded (`OpenVaultBackupSettings`): forgets the backup password, its
    /// status, the last backup event, the payload hash and the killphrase and
    /// search passphrase digesters of the vault that was open, and reads the
    /// open vault's. While the vault is locked there are none, so the Backups
    /// page never shows one vault's backups in another, and no vault's
    /// phrases are checked with another's keys.
    public func openVaultDidChange() async {
        openVaultChanges += 1
        let change = openVaultChanges
        backupPassword = .notFetched
        backupPasswordLoadingState = .notLoading
        backupPasswordStatus = .unknown
        lastBackupEvent = backupEventLogger.lastBackupEvent()
        currentPayloadHash = nil
        killphraseDigester = nil
        searchPassphraseDigester = nil
        // Each vault has keyrings of its own (`OpenVaultPhraseKeyrings`). A vault made before that takes its copy now.
        await loadKillphraseDigester()
        await loadSearchPassphraseDigester()
        guard change == openVaultChanges else { return }

        let status: BackupPasswordStatus
        do {
            status = try await backupPasswordStore.fetchPasswordMetadata().map { .set($0) } ?? .notSet
        } catch {
            // Locked, or it can't be read: it stays unknown.
            status = .unknown
        }
        guard change == openVaultChanges else { return }
        backupPasswordStatus = status

        let hash = try? await computeVaultHash()
        guard change == openVaultChanges else { return }
        currentPayloadHash = hash
    }
}

// MARK: - Backup Password

extension VaultDataModel {
    /// What it reads is dropped if another vault opens meanwhile: it's the previous vault's
    /// (`openVaultDidChange()`).
    public func loadBackupPassword() async {
        let change = openVaultChanges
        do {
            if case .fetched = backupPassword {
                return
            }
            backupPasswordLoadingState = .loading
            defer { backupPasswordLoadingState = .notLoading }
            let password = try await backupPasswordStore.fetchPassword()
            guard change == openVaultChanges else { return }
            if let password {
                backupPassword = .fetched(password)
                upgradeBackupPasswordIfNeeded(password, change: change)
                await markBackupPasswordStatusSet(change: change)
            } else {
                backupPassword = .notCreated
                backupPasswordStatus = .notSet
            }
        } catch {
            guard change == openVaultChanges else { return }
            backupPassword = .error(PresentationError(
                userTitle: "Encryption Key Error",
                userDescription: "Unable to load encryption key from storage",
                debugDescription: error.localizedDescription,
            ))
        }
    }

    /// Refreshes `backupPasswordStatus` without loading the password.
    public func loadBackupPasswordStatus() async {
        let change = openVaultChanges
        do {
            let metadata = try await backupPasswordStore.fetchPasswordMetadata()
            guard change == openVaultChanges else { return }
            if let metadata {
                backupPasswordStatus = .set(metadata)
            } else {
                backupPasswordStatus = .notSet
            }
        } catch {
            // A failed read says nothing new, so keep what's known: a status the user has already
            // seen mustn't disappear.
        }
    }

    public func store(backupPassword: DerivedEncryptionKey) async throws {
        let change = openVaultChanges
        backupPasswordWrites += 1
        try await backupPasswordStore.set(password: backupPassword)
        guard change == openVaultChanges else { return }
        self.backupPassword = .fetched(backupPassword)
        await markBackupPasswordStatusSet(change: change)
    }

    /// Moves the backup key just loaded to a stronger derivation, if Vault has one for it (VAULT-128), and stores it in
    /// place of the old one: the next time a backup password is loaded after the update, in the app.
    ///
    /// It takes seconds, so it runs in the background, while backups go on using `password`, which stays valid: a
    /// backup made with it restores as it always has. The new key is stored only if the same vault is open and no
    /// password has been set or removed since `password` was loaded, and the store replaces it all at once or not at
    /// all. If anything fails, the old key stays, nothing is said or logged, and it's tried again the next time it's
    /// loaded.
    private func upgradeBackupPasswordIfNeeded(_ password: DerivedEncryptionKey, change: Int) {
        guard let backupPasswordUpgrader, backupPasswordUpgrade == nil,
              password.keyDervier.storedBackupKeyUpgrade != nil
        else { return }
        let writes = backupPasswordWrites
        // At utility priority, as the derivation runs: awaiting it from a task of higher priority would raise it.
        backupPasswordUpgrade = Task(priority: .utility) { [weak self] in
            defer { self?.backupPasswordUpgrade = nil }
            guard let upgraded = try? await backupPasswordUpgrader.upgraded(password) else { return }
            guard let self, change == openVaultChanges, writes == backupPasswordWrites else { return }
            do {
                try await backupPasswordStore.upgradePassword(from: password, to: upgraded)
            } catch {
                return
            }
            // Backups use the new key from now on, unless the password has been forgotten or replaced meanwhile.
            guard change == openVaultChanges, backupPassword == .fetched(password) else { return }
            backupPassword = .fetched(upgraded)
        }
    }

    /// Waits for the backup key being moved to a stronger derivation, if one is.
    func finishUpgradingBackupPassword() async {
        await backupPasswordUpgrade?.value
    }

    /// Marks the backup password as set, once it's known to exist, unless another vault has opened since `change`.
    private func markBackupPasswordStatusSet(change: Int) async {
        // It's set, even if the store can't say when.
        let metadata = try? await backupPasswordStore.fetchPasswordMetadata()
        guard change == openVaultChanges else { return }
        backupPasswordStatus = .set(metadata ?? BackupPasswordMetadata(lastSetDate: nil))
    }
}

// MARK: - Fetching

extension VaultDataModel {
    /// Reloads all data in the model.
    public func reloadData() async {
        await reloadTags()
        await reloadItems()
    }

    /// Reloads only the items of the model, based on the current query.
    public func reloadItems() async {
        let generation = contentsGeneration
        do {
            let query = VaultStoreQuery(
                filterText: itemsSanitizedQuery,
                filterTags: itemsFilteringByTags,
            )
            // Killphrase matching requires the derived HMAC key, which is
            // only available when the vault is unlocked. If we don't have
            // one yet (vault still locked, key load failed), skip the
            // delete pass — the search itself remains functional.
            // Match on the same sanitized text the search predicate uses,
            // so a phrase the user can see matching in the feed also fires
            // the killphrase (digests are built from trimmed phrases).
            let didDeleteKillphraseItems: Bool = if let digester = killphraseDigester {
                await vaultKillphraseDeleter
                    .deleteItems(matchingKillphrase: itemsSanitizedQuery ?? itemsSearchQuery, using: digester)
            } else {
                false
            }
            let result = try await vaultStore.retrieve(
                query: query,
                searchPassphraseMatcher: searchPassphraseDigester,
            )
            // Purged for a lock while this was reading: what it read stays unseen.
            if generation == contentsGeneration {
                items = result.items
                itemErrors = result.errors
                itemsRetrievalError = nil
                if query == VaultStoreQuery() {
                    hasVisibleItems = Self.showsAnyItems(result)
                }
            }

            // If killphrase deletion occurred, sync OTP autofill store to remove deleted items
            if didDeleteKillphraseItems {
                try? await syncAllToOTPAutofillStore()
                // Refresh the payload hash before notifying, otherwise
                // auto-backup compares its last-backup hash against the
                // stale value and skips — leaving the deleted items
                // recoverable from the newest backup.
                await updateCurrentPayloadHash()
                // Notify downstream observers (auto-backup, widget reload) that
                // the item set changed silently from a killphrase match.
                onDataChanged?()
            }
        } catch {
            guard generation == contentsGeneration else { return }
            itemsRetrievalError = PresentationError(
                userTitle: "Error Loading",
                userDescription: "Unable to load items",
                debugDescription: error.localizedDescription,
            )
        }
    }

    /// Reads again whether the feed shows any item with no search or tag filter (`hasVisibleItems`), whatever search
    /// or filter is set. It deletes nothing and changes no other state.
    public func reloadHasVisibleItems() async {
        let generation = contentsGeneration
        guard let result = try? await vaultStore.retrieve(query: VaultStoreQuery()) else { return }
        // Purged for a lock while this was reading: what it read stays unseen.
        guard generation == contentsGeneration else { return }
        hasVisibleItems = Self.showsAnyItems(result)
    }

    /// Whether the feed would show anything for `result`, read with no search or tag filter. An item that couldn't be
    /// read counts, as one that shows.
    private static func showsAnyItems(_ result: VaultRetrievalResult<VaultItem>) -> Bool {
        result.totalItems > 0
    }

    /// Reloads only the tags of the model.
    public func reloadTags() async {
        let generation = contentsGeneration
        do {
            let tags = try await vaultTagStore.retrieveTags()
            // Purged for a lock while this was reading: what it read stays unseen.
            guard generation == contentsGeneration else { return }
            allTags = tags
            allTagsState = .loaded
        } catch {
            guard generation == contentsGeneration else { return }
            allTagsRetrievalError = PresentationError(
                userTitle: "Error Loading",
                userDescription: "Unable to load tags",
                debugDescription: error.localizedDescription,
            )
        }
    }
}

// MARK: - Writing

extension VaultDataModel {
    public func insert(item: VaultItem.Write) async throws {
        let itemID = try await vaultStore.insert(item: item)
        await reloadItems()
        // Individual sync works for inserts since there's no old value to worry about
        try? await vaultOtpAutofillStore.sync(id: itemID.rawValue, item: item)
        await updateCurrentPayloadHash()
        onDataChanged?()
    }

    public func update(itemID id: Identifier<VaultItem>, data: VaultItem.Write) async throws {
        try await vaultStore.update(id: id, item: data)
        await invalidateCaches(itemID: id)
        await reloadItems()
        await updateCurrentPayloadHash()
        // Must do full sync for updates because we don't have access to old values
        // to construct a matching identity for removal. Attempting individual remove
        // with new values won't match the existing identity with old values.
        try? await syncAllToOTPAutofillStore()
        onDataChanged?()
    }

    public func delete(itemID: Identifier<VaultItem>) async throws {
        try await vaultStore.delete(id: itemID)
        await invalidateCaches(itemID: itemID)
        await reloadItems()
        await updateCurrentPayloadHash()
        // Full sync for deletes to ensure removal works reliably
        try? await syncAllToOTPAutofillStore()
        onDataChanged?()
    }

    public func reorder(items: Set<Identifier<VaultItem>>, to position: VaultReorderingPosition) async throws {
        try await vaultStore.reorder(items: items, to: position)
        // don't reload, assume UI state has reordered items directly
        await updateCurrentPayloadHash()
        onDataChanged?()
    }

    public func insert(tag: VaultItemTag.Write) async throws {
        try await vaultTagStore.insertTag(item: tag)
        await reloadTags()
        await updateCurrentPayloadHash()
        onDataChanged?()
    }

    public func update(tagID id: Identifier<VaultItemTag>, data: VaultItemTag.Write) async throws {
        try await vaultTagStore.updateTag(id: id, item: data)
        await reloadTags()
        await updateCurrentPayloadHash()
        onDataChanged?()
    }

    public func delete(tagID: Identifier<VaultItemTag>) async throws {
        try await vaultTagStore.deleteTag(id: tagID)
        await reloadTags()
        itemsFilteringByTags.remove(tagID)
        await reloadItems()
        await updateCurrentPayloadHash()
        onDataChanged?()
    }
}

extension VaultDataModel: VaultStoreHOTPIncrementer {
    public func incrementCounter(id: Identifier<VaultItem>) async throws {
        try await vaultStore.incrementCounter(id: id)
        await reloadItems()
        await updateCurrentPayloadHash()
        onDataChanged?()
    }

    /// Advances a HOTP code's counter for a widget's link, as the widget itself would: only for a code a widget may
    /// show (`VaultItemWidgetEligibility`). Anything else the link names, whether it's locked, hidden, not a HOTP code
    /// or not in the vault at all, is left as it is, and all of them look the same to the caller.
    public func incrementCounterIfWidgetEligible(id: Identifier<VaultItem>) async throws {
        let items = try await vaultStore.retrieve(query: .init()).items
        guard let item = items.first(where: { $0.id == id }),
              VaultItemWidgetEligibility.isEligible(item),
              case let .otpCode(code) = item.item,
              case .hotp = code.type
        else { return }
        try await incrementCounter(id: id)
    }
}

extension VaultDataModel: VaultStoreEncryptedItemReplacer {
    /// Encrypts an item again without changing anything else about it, as `EncryptedItemDetailViewModel` does to move
    /// it to a stronger key derivation (VAULT-128). Then the vault has changed, so it's handled as any other change,
    /// auto-backup included. Encrypted items are never offered to AutoFill, so its suggestions stay as they are.
    public func replaceEncryptedItem(
        id: Identifier<VaultItem>,
        _ old: EncryptedItem,
        with new: EncryptedItem,
    ) async throws -> Bool {
        guard try await vaultStore.replaceEncryptedItem(id: id, old, with: new) else { return false }
        await invalidateCaches(itemID: id)
        await reloadItems()
        await updateCurrentPayloadHash()
        onDataChanged?()
        return true
    }
}

// MARK: - Import

extension VaultDataModel {
    public func importMerge(payload: VaultApplicationPayload) async throws {
        try await addKeysFromBackup(of: payload)
        try await vaultImporter.importAndMergeVault(payload: payload)
        await reloadItems()
        await reloadTags()
        await updateCurrentPayloadHash()
        try? await syncAllToOTPAutofillStore()
        onDataChanged?()
    }

    public func importOverride(payload: VaultApplicationPayload) async throws {
        try await addKeysFromBackup(of: payload)
        try await vaultImporter.importAndOverrideVault(payload: payload)
        await reloadItems()
        await reloadTags()
        await updateCurrentPayloadHash()
        try? await syncAllToOTPAutofillStore()
        onDataChanged?()
    }

    /// Adds the keys a backup brought to the open vault's keyrings, before its items are imported, and makes the
    /// digesters again with them, so its killphrases and search passphrases match here as they did where it was made.
    /// An encrypted vault keeps them in its payload, and the plain store in the keychain (`OpenVaultPhraseKeyrings`).
    /// If the keys can't be added, nothing's imported.
    ///
    /// A backup made before the keys went with it brings none. Its phrases only match where the keys they were
    /// digested with are still on the vault's keyrings.
    private func addKeysFromBackup(of payload: VaultApplicationPayload) async throws {
        guard payload.killphraseKeys.isNotEmpty || payload.searchPassphraseKeys.isNotEmpty else { return }
        let change = openVaultChanges
        try await killphraseKeyStore.addKeysFromBackup(payload.killphraseKeys)
        try await searchPassphraseKeyStore.addKeysFromBackup(payload.searchPassphraseKeys)
        let killphraseDigester = try? await makeKillphraseDigester()
        let searchPassphraseDigester = try? await makeSearchPassphraseDigester()
        // Another vault's keys mustn't check this one's phrases.
        guard change == openVaultChanges else { return }
        if let killphraseDigester {
            self.killphraseDigester = killphraseDigester
        }
        if let searchPassphraseDigester {
            self.searchPassphraseDigester = searchPassphraseDigester
        }
    }
}

// MARK: - Export

extension VaultDataModel {
    /// The open vault, for a backup or a move to another device, with every key on its killphrase and search
    /// passphrase keyrings. The keys go with the vault so its phrases still work wherever it's restored.
    public func makeExport(userDescription: String) async throws -> VaultApplicationPayload {
        // No need to refetch items, this export is pulled directly from the store.
        var payload = try await vaultStore.exportVault(userDescription: userDescription)
        payload.killphraseKeys = try await killphraseKeyStore.loadKeyring()
        payload.searchPassphraseKeys = try await searchPassphraseKeyStore.loadKeyring()
        return payload
    }
}

// MARK: - Delete

extension VaultDataModel {
    /// Deletes every item and tag in the open vault, the codes AutoFill suggests, and the vault's backup password.
    ///
    /// The backup password goes too (VAULT-60): it's the key to every backup of what was just deleted, so it goes with
    /// the data. Restoring never uses it, since a backup always asks for the password it was made with. An erase
    /// deletes it for the same reason. Backups, auto-backup's configuration and the app's settings stay.
    ///
    /// Deleting an encrypted vault's data destroys every other vault, so the keychain's killphrase and search
    /// passphrase keyrings that only those vaults could need go too (`PhraseKeyringsCleanup`). The open vault keeps
    /// its own.
    public func deleteVault() async throws {
        try await vaultDeleter.deleteVault()
        // Reload and notify before the rest, so nothing keeps showing items that are already gone if that fails.
        await reloadItems()
        await reloadTags()
        onVaultDeleted?()
        // Each is tried whether or not the other fails, and deleting again finishes whatever didn't.
        var failure: (any Error)?
        do {
            try await removeBackupPassword()
        } catch {
            failure = error
        }
        do {
            try await vaultOtpAutofillStore.removeAll()
        } catch {
            failure = failure ?? error
        }
        do {
            try await phraseKeyringsCleanup?.deleteKeyringsNoOtherVaultNeeds()
        } catch {
            failure = failure ?? error
        }
        if let failure {
            throw failure
        }
    }

    private func removeBackupPassword() async throws {
        let change = openVaultChanges
        backupPasswordWrites += 1
        try await backupPasswordStore.removePassword()
        guard change == openVaultChanges else { return }
        backupPassword = .notCreated
        backupPasswordStatus = .notSet
    }
}

// MARK: - OTP Autofill Store

extension VaultDataModel {
    public func clearOTPAutofillStore() async throws {
        try await vaultOtpAutofillStore.removeAll()
    }

    public func getOTPAutofillStoreIdentities() async throws -> [ASOneTimeCodeCredentialIdentity] {
        try await vaultOtpAutofillStore.getAllIdentities()
    }

    public func removeOTPItemFromAutofillStore(id: UUID) async throws {
        try await vaultOtpAutofillStore.remove(id: id, code: nil)
    }

    public func getOTPAutofillStoreState() async -> ASCredentialIdentityStoreState {
        await vaultOtpAutofillStore.getState()
    }

    /// Performs a full sync of all vault items to the autofill store.
    /// Removes all existing items and repopulates with all OTP items from the vault.
    /// The codes Spotlight should hold now (see `SpotlightCode`), from every item the open vault shows without a
    /// search: never the feed's `items`, which follow its search and tag filters.
    public func spotlightCodes(isTurnedOn: Bool, isAppLockOn: Bool) async throws -> [SpotlightCode] {
        guard isTurnedOn, !isAppLockOn else { return [] }
        let result = try await vaultStore.retrieve(query: .init())
        return SpotlightCode.codes(in: result.items, isTurnedOn: isTurnedOn, isAppLockOn: isAppLockOn)
    }

    public func syncAllToOTPAutofillStore() async throws {
        let result = try await vaultStore.retrieve(query: .init())
        try await vaultOtpAutofillStore.syncAll(items: result.items)
    }
}
