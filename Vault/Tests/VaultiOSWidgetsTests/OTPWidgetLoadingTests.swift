import Foundation
import TestHelpers
import Testing
import VaultCore
import VaultFeed
@testable import VaultiOSWidgets

struct OTPWidgetLoadingTests {
    @Test
    func eligibleItems_retriesAfterStoreOpenFailure() async throws {
        let item = makeOTPVaultItem(accountName: "first", issuer: "Issuer")
        let store = FakeVaultStoreReader(results: [.success(.init(items: [item]))])
        let factory = StoreFactoryScript(results: [
            .failure(.open),
            .success(store),
        ])
        let loader = WidgetVaultLoader(isVaultPlain: { true }, makeStore: { try factory.makeStore() })

        await #expect(throws: WidgetTestError.open) {
            try await loader.eligibleItems()
        }
        let items = try await loader.eligibleItems()

        #expect(items == [item])
        #expect(factory.openCallCount == 2)
        #expect(await store.retrieveCallCount == 1)
    }

    /// Once the vault is encrypted, or while it's being converted, the plain store mustn't be opened.
    @Test
    func eligibleItems_whenTheVaultIsNotPlain_neverOpensTheStore() async throws {
        let item = makeOTPVaultItem(accountName: "first", issuer: "Issuer")
        let factory = StoreFactoryScript(results: [.success(FakeVaultStoreReader(results: [
            .success(.init(items: [item])),
        ]))])
        let loader = WidgetVaultLoader(isVaultPlain: { false }, makeStore: { try factory.makeStore() })

        let items = try await loader.eligibleItems()

        #expect(items == [])
        #expect(factory.openCallCount == 0)
    }

    @Test
    func eligibleItems_clearsCachedStoreAfterRetrieveFailure() async throws {
        let item = makeOTPVaultItem(accountName: "second", issuer: "Issuer")
        let failingStore = FakeVaultStoreReader(results: [.failure(.retrieve)])
        let succeedingStore = FakeVaultStoreReader(results: [.success(.init(items: [item]))])
        let factory = StoreFactoryScript(results: [
            .success(failingStore),
            .success(succeedingStore),
        ])
        let loader = WidgetVaultLoader(isVaultPlain: { true }, makeStore: { try factory.makeStore() })

        await #expect(throws: WidgetTestError.retrieve) {
            try await loader.eligibleItems()
        }
        let items = try await loader.eligibleItems()

        #expect(items == [item])
        #expect(factory.openCallCount == 2)
        #expect(await failingStore.retrieveCallCount == 1)
        #expect(await succeedingStore.retrieveCallCount == 1)
    }

    @Test
    func suggestedEntities_returnEmptyOnFailureThenReturnEligibleCodesAfterRetry() async throws {
        let item = makeOTPVaultItem(accountName: "account", issuer: "issuer")
        let store = FakeVaultStoreReader(results: [.success(.init(items: [item]))])
        let factory = StoreFactoryScript(results: [
            .failure(.open),
            .success(store),
        ])
        let query = OTPWidgetItemEntityQuery(loader: WidgetVaultLoader(
            isVaultPlain: { true },
            makeStore: { try factory.makeStore() },
        ))

        let firstResult = try await query.suggestedEntities()
        let secondResult = try await query.suggestedEntities()

        #expect(firstResult == [])
        #expect(secondResult == [
            OTPWidgetItemEntity(
                id: item.id.rawValue,
                issuer: "issuer",
                accountName: "account",
            ),
        ])
        #expect(factory.openCallCount == 2)
    }

    @Test
    func entitiesForIdentifiers_returnEmptyOnFailure() async throws {
        let id = UUID()
        let query = OTPWidgetItemEntityQuery(loader: WidgetVaultLoader(isVaultPlain: { true }, makeStore: {
            throw WidgetTestError.open
        }))

        let entities = try await query.entities(for: [id])

        #expect(entities == [])
    }

    @Test
    func eligibleItems_filtersIneligibleItems() async throws {
        let eligible = makeOTPVaultItem(accountName: "eligible")
        let store = FakeVaultStoreReader(results: [.success(.init(items: [
            eligible,
            makeOTPVaultItem(accountName: "locked", lockState: .lockedWithNativeSecurity),
            makeOTPVaultItem(accountName: "hidden", visibility: .onlySearch),
            makeOTPVaultItem(accountName: "passphrase", searchableLevel: .onlyPassphrase),
            makeOTPVaultItem(
                accountName: "killphrase",
                killphrase: .init(salt: Data([1]), digest: Data([2])),
            ),
            makeSecureNoteVaultItem(),
        ]))])
        let loader = WidgetVaultLoader(store: store)

        let items = try await loader.eligibleItems()

        #expect(items == [eligible])
    }

    @Test
    func providerTimeline_isUnavailableWhenSelectionIsMissing() async {
        let provider = OTPWidgetProvider(loader: WidgetVaultLoader(store: FakeVaultStoreReader(results: [])))

        let timeline = await provider.makeTimeline(for: .init(item: nil))

        #expect(timeline.entries.first?.snapshot == .unavailable)
    }

    @Test
    func providerTimeline_appLockOn_isLockedWithoutReadingTheVault() async throws {
        let item = makeOTPVaultItem(accountName: "account", issuer: "issuer")
        let store = FakeVaultStoreReader(results: [.success(.init(items: [item]))])
        let provider = try OTPWidgetProvider(loader: WidgetVaultLoader(store: store, appLockSettings: appLockOn()))
        let entity = OTPWidgetItemEntity(id: item.id.rawValue, issuer: "issuer", accountName: "account")

        let timeline = await provider.makeTimeline(for: .init(item: entity))

        #expect(timeline.entries.map(\.snapshot) == [.locked])
        #expect(await store.retrieveCallCount == 0)
    }

    @Test
    func providerTimeline_appLockOff_showsTheCode() async throws {
        let item = makeOTPVaultItem(accountName: "account", issuer: "issuer")
        let store = FakeVaultStoreReader(results: [.success(.init(items: [item]))])
        let settings = try AppLockSettingsStore(userDefaults: .nonPersistent())
        let provider = OTPWidgetProvider(loader: WidgetVaultLoader(store: store, appLockSettings: settings))
        let entity = OTPWidgetItemEntity(id: item.id.rawValue, issuer: "issuer", accountName: "account")

        let timeline = await provider.makeTimeline(for: .init(item: entity))

        guard case let .totp(totp) = timeline.entries.first?.snapshot else {
            Issue.record("Expected a TOTP entry, got \(String(describing: timeline.entries.first?.snapshot))")
            return
        }
        #expect(totp.itemID == item.id.rawValue)
    }

    @Test
    func suggestedEntities_appLockOn_listNothing() async throws {
        // The widget's configuration can't be used to list the vault's items while the lock is on.
        let item = makeOTPVaultItem(accountName: "account", issuer: "issuer")
        let store = FakeVaultStoreReader(results: [.success(.init(items: [item]))])
        let query = try OTPWidgetItemEntityQuery(loader: WidgetVaultLoader(store: store, appLockSettings: appLockOn()))

        let entities = try await query.suggestedEntities()

        #expect(entities == [])
        #expect(await store.retrieveCallCount == 0)
    }

    @Test
    func providerTimeline_isUnavailableWhenSelectedItemFailsToLoad() async {
        let entity = OTPWidgetItemEntity(id: UUID(), issuer: "issuer", accountName: "account")
        let provider = OTPWidgetProvider(loader: WidgetVaultLoader(store: FakeVaultStoreReader(results: [
            .failure(.retrieve),
        ])))

        let timeline = await provider.makeTimeline(for: .init(item: entity))

        #expect(timeline.entries.first?.snapshot == .unavailable)
    }
}

private func appLockOn() throws -> AppLockSettingsStore {
    let settings = try AppLockSettingsStore(userDefaults: .nonPersistent())
    settings.isEnabled = true
    return settings
}

private enum WidgetTestError: Error, Equatable {
    case open
    case retrieve
}

// Test-only synchronous factory. `WidgetVaultLoader.StoreFactory` is synchronous,
// so actor isolation cannot model its scripted open sequence.
// swiftlint:disable:next no_unchecked_sendable
private final class StoreFactoryScript: @unchecked Sendable {
    enum Result {
        case failure(WidgetTestError)
        case success(any WidgetVaultLoader.WidgetStore)
    }

    private var results: [Result]
    private(set) var openCallCount = 0

    init(results: [Result]) {
        self.results = results
    }

    func makeStore() throws -> any WidgetVaultLoader.WidgetStore {
        openCallCount += 1
        let result = results.isEmpty ? .failure(.open) : results.removeFirst()
        switch result {
        case let .failure(error):
            throw error
        case let .success(store):
            return store
        }
    }
}

private actor FakeVaultStoreReader: VaultStoreHOTPIncrementer, VaultStoreReader {
    private var results: [Result<VaultRetrievalResult<VaultItem>, WidgetTestError>]
    private(set) var retrieveCallCount = 0
    private(set) var incrementedIDs = [Identifier<VaultItem>]()

    init(results: [Result<VaultRetrievalResult<VaultItem>, WidgetTestError>]) {
        self.results = results
    }

    func retrieve(
        query _: VaultStoreQuery,
        searchPassphraseMatcher _: (any SearchPassphraseMatcher)?,
    ) async throws -> VaultRetrievalResult<VaultItem> {
        retrieveCallCount += 1
        let result = results.isEmpty ? .success(.empty()) : results.removeFirst()
        switch result {
        case let .success(items):
            return items
        case let .failure(error):
            throw error
        }
    }

    func incrementCounter(id: Identifier<VaultItem>) async throws {
        incrementedIDs.append(id)
    }

    var hasAnyItems: Bool {
        get async throws { true }
    }
}

private func makeOTPVaultItem(
    id: Identifier<VaultItem> = .new(),
    accountName: String = "",
    issuer: String = "",
    visibility: VaultItemVisibility = .always,
    searchableLevel: VaultItemSearchableLevel = .full,
    killphrase: KillphraseDigest? = nil,
    lockState: VaultItemLockState = .notLocked,
) -> VaultItem {
    makeVaultItem(
        id: id,
        item: .otpCode(.init(
            type: .totp(),
            data: .init(
                secret: .init(data: Data(repeating: 1, count: 20), format: .base32),
                accountName: accountName,
                issuer: issuer,
            ),
        )),
        visibility: visibility,
        searchableLevel: searchableLevel,
        killphrase: killphrase,
        lockState: lockState,
    )
}

private func makeSecureNoteVaultItem() -> VaultItem {
    makeVaultItem(item: .secureNote(.init(title: "note", contents: "contents", format: .plain)))
}

private func makeVaultItem(
    id: Identifier<VaultItem> = .new(),
    item: VaultItem.Payload,
    visibility: VaultItemVisibility = .always,
    searchableLevel: VaultItemSearchableLevel = .full,
    killphrase: KillphraseDigest? = nil,
    lockState: VaultItemLockState = .notLocked,
) -> VaultItem {
    let date = Date(timeIntervalSince1970: 0)
    return VaultItem(
        metadata: .init(
            id: id,
            created: date,
            updated: date,
            relativeOrder: 0,
            userDescription: "",
            tags: [],
            visibility: visibility,
            searchableLevel: searchableLevel,
            searchPassphrase: nil,
            killphrase: killphrase,
            lockState: lockState,
            color: nil,
            showInQuickType: true,
            previewMode: .titleAndFirstLine,
        ),
        item: item,
    )
}
