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
    public private(set) var hasAnyItems = false
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

    /// Derived from the unlocked vault key. Cached here so the killphrase
    /// match and write paths can avoid redoing HKDF on every keystroke.
    /// `nil` whenever the vault is not currently unlocked.
    public private(set) var killphraseDigester: KillphraseDigester?

    /// Cached search-passphrase HMAC digester. Same lifecycle as
    /// `killphraseDigester` — loaded on `setup()`, retained across the
    /// unlocked-device session, used for both the live search predicate
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
    private let backupEventLogger: any BackupEventLogger
    private var observationBag = Set<AnyCancellable>()
    /// Counts `purgeVaultContents()` calls. A reload that started before the
    /// latest one is out of date by the time it finishes, so it's dropped.
    @ObservationIgnored private var contentsGeneration = 0

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

        monitorBackupEvents()
    }

    /// Initial setup to ensure the model is in a good state.
    public func setup() async {
        await loadKillphraseDigester()
        await loadSearchPassphraseDigester()
        await updateCurrentPayloadHash()
    }

    /// Loads or generates the killphrase HMAC key and caches a digester
    /// for the lifetime of the unlocked-device session. Safe to call
    /// multiple times — no-op if digester is already built.
    public func loadKillphraseDigester() async {
        if killphraseDigester != nil {
            return
        }
        do {
            let key = try await killphraseKeyStore.loadOrCreate()
            let digester = KillphraseDigester(key: key)
            killphraseDigester = digester
            // Phase B of the V1 → V2 killphrase migration. Idempotent;
            // does nothing if there are no pending entries. Best-effort —
            // failure here must not block normal startup.
            await killphraseRehashService?.run(using: digester)
        } catch {
            // Silent failure: we don't want to surface an alert here. The
            // killphrase deleter will simply remain a no-op until next
            // launch. No telemetry per MANIFESTO C3.
        }
    }

    /// Loads or generates the search-passphrase HMAC key and caches a
    /// digester for the lifetime of the unlocked-device session. Same
    /// shape as `loadKillphraseDigester`; failure leaves passphrase
    /// matching disabled until next launch.
    public func loadSearchPassphraseDigester() async {
        if searchPassphraseDigester != nil {
            return
        }
        do {
            let key = try await searchPassphraseKeyStore.loadOrCreate()
            let digester = SearchPassphraseDigester(key: key)
            searchPassphraseDigester = digester
            // Phase B of the V2 → V3 search-passphrase migration.
            await searchPassphraseRehashService?.run(using: digester)
        } catch {
            // Silent failure per MANIFESTO C3.
        }
    }

    private func monitorBackupEvents() {
        lastBackupEvent = backupEventLogger.lastBackupEvent()
        backupEventLogger.loggedEventPublisher.sink { [weak self] newEvent in
            self?.lastBackupEvent = newEvent
        }.store(in: &observationBag)
    }

    /// Updates the current payload hash in the background.
    private func updateCurrentPayloadHash() async {
        currentPayloadHash = try? await computeVaultHash()
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
        // killphraseDigester is intentionally NOT cleared. The key it
        // wraps is a device-bound HMAC key (not the user's password), is
        // re-fetched silently from keychain on next launch, and clearing
        // it would break killphrase deletion until the next setup call.
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
        hasAnyItems = false
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

// MARK: - Backup Password

extension VaultDataModel {
    public func loadBackupPassword() async {
        do {
            if case .fetched = backupPassword {
                return
            }
            backupPasswordLoadingState = .loading
            defer { backupPasswordLoadingState = .notLoading }
            let password = try await backupPasswordStore.fetchPassword()
            if let password {
                backupPassword = .fetched(password)
                await markBackupPasswordStatusSet()
            } else {
                backupPassword = .notCreated
                backupPasswordStatus = .notSet
            }
        } catch {
            backupPassword = .error(PresentationError(
                userTitle: "Encryption Key Error",
                userDescription: "Unable to load encryption key from storage",
                debugDescription: error.localizedDescription,
            ))
        }
    }

    /// Refreshes `backupPasswordStatus` without loading the password.
    public func loadBackupPasswordStatus() async {
        do {
            if let metadata = try await backupPasswordStore.fetchPasswordMetadata() {
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
        try await backupPasswordStore.set(password: backupPassword)
        self.backupPassword = .fetched(backupPassword)
        await markBackupPasswordStatusSet()
    }

    /// Marks the backup password as set, once it's known to exist.
    private func markBackupPasswordStatusSet() async {
        // It's set, even if the store can't say when.
        let metadata = try? await backupPasswordStore.fetchPasswordMetadata()
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
            let hasAnyItems = try await vaultStore.hasAnyItems
            // Purged for a lock while this was reading: what it read stays unseen.
            if generation == contentsGeneration {
                items = result.items
                itemErrors = result.errors
                itemsRetrievalError = nil
                self.hasAnyItems = hasAnyItems
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
        try? await vaultOtpAutofillStore.sync(
            id: itemID.rawValue,
            item: item.item,
            visibility: item.visibility,
            searchableLevel: item.searchableLevel,
            showInQuickType: item.showInQuickType,
        )
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
}

// MARK: - Import

extension VaultDataModel {
    public func importMerge(payload: VaultApplicationPayload) async throws {
        try await vaultImporter.importAndMergeVault(payload: payload)
        await reloadItems()
        await reloadTags()
        await updateCurrentPayloadHash()
        try? await syncAllToOTPAutofillStore()
        onDataChanged?()
    }

    public func importOverride(payload: VaultApplicationPayload) async throws {
        try await vaultImporter.importAndOverrideVault(payload: payload)
        await reloadItems()
        await reloadTags()
        await updateCurrentPayloadHash()
        try? await syncAllToOTPAutofillStore()
        onDataChanged?()
    }
}

// MARK: - Export

extension VaultDataModel {
    public func makeExport(userDescription: String) async throws -> VaultApplicationPayload {
        // No need to refetch items, this export is pulled directly from the store.
        try await vaultStore.exportVault(userDescription: userDescription)
    }
}

// MARK: - Delete

extension VaultDataModel {
    public func deleteVault() async throws {
        try await vaultDeleter.deleteVault()
        // Reload and notify before clearing AutoFill, so nothing keeps showing items that are already gone if that
        // fails.
        await reloadItems()
        await reloadTags()
        onVaultDeleted?()
        try await vaultOtpAutofillStore.removeAll()
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
    public func syncAllToOTPAutofillStore() async throws {
        let result = try await vaultStore.retrieve(query: .init())
        try await vaultOtpAutofillStore.syncAll(items: result.items)
    }
}
