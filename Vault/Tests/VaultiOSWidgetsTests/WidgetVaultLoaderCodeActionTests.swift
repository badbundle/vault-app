import Foundation
import TestHelpers
import Testing
import VaultCore
import VaultFeed
@testable import VaultiOSWidgets

/// Covers the two code-producing paths the widget's `AppIntent`s call.
///
/// The eligibility gate matters most here: an intent fires from a widget the
/// user tapped, outside any auth prompt, so an ineligible item must yield no
/// code and — for HOTP — must not advance the counter.
struct WidgetVaultLoaderCodeActionTests {
    // MARK: - HOTP

    @Test
    func incrementAndRenderHOTPCode_advancesCounterAndReturnsCode() async throws {
        let item = makeHOTPVaultItem(counter: 4)
        let store = IncrementingFakeStore(items: [item])
        let loader = WidgetVaultLoader(store: store)

        let code = try await loader.incrementAndRenderHOTPCode(id: item.id.rawValue)

        #expect(code != nil)
        #expect(await store.incrementedIDs == [item.id])
    }

    @Test
    func incrementAndRenderHOTPCode_rendersTheNextCounterNotTheCurrentOne() async throws {
        let item = makeHOTPVaultItem(counter: 4)
        let loader = WidgetVaultLoader(store: IncrementingFakeStore(items: [item]))

        let code = try await loader.incrementAndRenderHOTPCode(id: item.id.rawValue)

        let expected = try HOTPAuthCode(counter: UInt64(5), data: hotpData()).renderCode()
        #expect(code == expected)
    }

    /// While the vault is encrypted with the App Lock Password, a widget can't advance a counter, even with the
    /// app lock's setting off.
    @Test
    func incrementAndRenderHOTPCode_vaultEncrypted_isUnavailable() async throws {
        let item = makeHOTPVaultItem(counter: 4)
        let store = IncrementingFakeStore(items: [item])
        let loader = try WidgetVaultLoader(
            appLockSettings: AppLockSettingsStore(userDefaults: .nonPersistent()),
            isVaultPlain: { false },
            makeStore: { store },
        )

        let code = try await loader.incrementAndRenderHOTPCode(id: item.id.rawValue)

        #expect(code == nil)
        #expect(await store.incrementedIDs == [])
    }

    @Test
    func incrementAndRenderHOTPCode_ineligibleItemDoesNotIncrement() async throws {
        let item = makeHOTPVaultItem(counter: 1, lockState: .lockedWithNativeSecurity)
        let store = IncrementingFakeStore(items: [item])
        let loader = WidgetVaultLoader(store: store)

        let code = try await loader.incrementAndRenderHOTPCode(id: item.id.rawValue)

        #expect(code == nil)
        #expect(await store.incrementedIDs.isEmpty)
    }

    @Test
    func incrementAndRenderHOTPCode_killphraseItemDoesNotIncrement() async throws {
        let item = makeHOTPVaultItem(counter: 1, killphrase: .init(salt: Data([1]), digest: Data([2])))
        let store = IncrementingFakeStore(items: [item])
        let loader = WidgetVaultLoader(store: store)

        let code = try await loader.incrementAndRenderHOTPCode(id: item.id.rawValue)

        #expect(code == nil)
        #expect(await store.incrementedIDs.isEmpty)
    }

    @Test
    func incrementAndRenderHOTPCode_totpItemReturnsNil() async throws {
        let item = makeTOTPVaultItem()
        let store = IncrementingFakeStore(items: [item])
        let loader = WidgetVaultLoader(store: store)

        let code = try await loader.incrementAndRenderHOTPCode(id: item.id.rawValue)

        #expect(code == nil)
        #expect(await store.incrementedIDs.isEmpty)
    }

    @Test
    func incrementAndRenderHOTPCode_unknownItemReturnsNil() async throws {
        let store = IncrementingFakeStore(items: [])
        let loader = WidgetVaultLoader(store: store)

        let code = try await loader.incrementAndRenderHOTPCode(id: UUID())

        #expect(code == nil)
        #expect(await store.incrementedIDs.isEmpty)
    }

    // MARK: - TOTP

    @Test
    func currentTOTPCode_returnsCodeForEligibleItem() async throws {
        let item = makeTOTPVaultItem()
        let loader = WidgetVaultLoader(store: IncrementingFakeStore(items: [item]))

        let code = try await loader.currentTOTPCode(id: item.id.rawValue, date: Date(timeIntervalSince1970: 0))

        #expect(code != nil)
    }

    @Test
    func currentTOTPCode_ineligibleItemReturnsNil() async throws {
        let item = makeTOTPVaultItem(visibility: .onlySearch)
        let loader = WidgetVaultLoader(store: IncrementingFakeStore(items: [item]))

        let code = try await loader.currentTOTPCode(id: item.id.rawValue)

        #expect(code == nil)
    }

    @Test
    func currentTOTPCode_hotpItemReturnsNil() async throws {
        let item = makeHOTPVaultItem(counter: 1)
        let loader = WidgetVaultLoader(store: IncrementingFakeStore(items: [item]))

        let code = try await loader.currentTOTPCode(id: item.id.rawValue)

        #expect(code == nil)
    }

    // MARK: - App lock

    @Test
    func currentTOTPCode_appLockOn_returnsNil() async throws {
        let item = makeTOTPVaultItem()
        let loader = try WidgetVaultLoader(store: IncrementingFakeStore(items: [item]), appLockSettings: appLockOn())

        let code = try await loader.currentTOTPCode(id: item.id.rawValue)

        #expect(code == nil)
    }

    @Test
    func incrementAndRenderHOTPCode_appLockOn_doesNotIncrement() async throws {
        let item = makeHOTPVaultItem(counter: 1)
        let store = IncrementingFakeStore(items: [item])
        let loader = try WidgetVaultLoader(store: store, appLockSettings: appLockOn())

        let code = try await loader.incrementAndRenderHOTPCode(id: item.id.rawValue)

        #expect(code == nil)
        #expect(await store.incrementedIDs.isEmpty)
    }

    private func appLockOn() throws -> AppLockSettingsStore {
        let settings = try AppLockSettingsStore(userDefaults: .nonPersistent())
        settings.isEnabled = true
        return settings
    }
}

// MARK: - Helpers

private actor IncrementingFakeStore: VaultStoreHOTPIncrementer, VaultStoreReader {
    private let items: [VaultItem]
    private(set) var incrementedIDs = [Identifier<VaultItem>]()

    init(items: [VaultItem]) {
        self.items = items
    }

    func retrieve(
        query _: VaultStoreQuery,
        searchPassphraseMatcher _: (any SearchPassphraseMatcher)?,
    ) async throws -> VaultRetrievalResult<VaultItem> {
        .init(items: items)
    }

    func incrementCounter(id: Identifier<VaultItem>) async throws {
        incrementedIDs.append(id)
    }

    var hasAnyItems: Bool {
        get async throws { items.isNotEmpty }
    }
}

private func hotpData() -> OTPAuthCodeData {
    .init(
        secret: .init(data: Data(repeating: 1, count: 20), format: .base32),
        accountName: "account",
        issuer: "Issuer",
    )
}

private func makeHOTPVaultItem(
    counter: UInt64,
    killphrase: KillphraseDigest? = nil,
    lockState: VaultItemLockState = .notLocked,
) -> VaultItem {
    makeItem(
        payload: .otpCode(.init(type: .hotp(counter: counter), data: hotpData())),
        visibility: .always,
        killphrase: killphrase,
        lockState: lockState,
    )
}

private func makeTOTPVaultItem(visibility: VaultItemVisibility = .always) -> VaultItem {
    makeItem(
        payload: .otpCode(.init(type: .totp(), data: hotpData())),
        visibility: visibility,
        killphrase: nil,
        lockState: .notLocked,
    )
}

private func makeItem(
    payload: VaultItem.Payload,
    visibility: VaultItemVisibility,
    killphrase: KillphraseDigest?,
    lockState: VaultItemLockState,
) -> VaultItem {
    VaultItem(
        metadata: .init(
            id: .new(),
            created: Date(timeIntervalSince1970: 0),
            updated: Date(timeIntervalSince1970: 0),
            relativeOrder: .min,
            userDescription: "any",
            tags: [],
            visibility: visibility,
            searchableLevel: .full,
            searchPassphrase: nil,
            killphrase: killphrase,
            lockState: lockState,
            color: nil,
            showInQuickType: true,
            previewMode: .titleAndFirstLine,
        ),
        item: payload,
    )
}
