import Foundation
import FoundationExtensions
import TestHelpers
import Testing
import VaultCore
import VaultFeed
@testable import VaultiOSWidgets

/// Covers the two code-producing paths the widget's `AppIntent`s call.
///
/// The eligibility gate matters most here: an intent fires from a widget the
/// user tapped, without opening Vault, so an ineligible item must yield no
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
            accessMode: { .password },
            makeStore: { _ in store },
        )

        let code = try await loader.incrementAndRenderHOTPCode(id: item.id.rawValue)

        #expect(code == nil)
        #expect(await store.incrementedIDs == [])
    }

    /// With the password off, the widget only reads the vault the device key opens: it hasn't the memory to save the
    /// whole file. The app advances the counter instead, through a link, so this does nothing, as for a link left from
    /// before.
    @Test
    func incrementAndRenderHOTPCode_passwordOff_leavesItToTheApp() async throws {
        let item = makeHOTPVaultItem(counter: 4)
        let store = IncrementingFakeStore(items: [item])
        let opens = SharedMutex(0)
        let loader = try WidgetVaultLoader(
            appLockSettings: AppLockSettingsStore(userDefaults: .nonPersistent()),
            accessMode: { .deviceKey },
            makeStore: { _ in
                opens.modify { $0 += 1 }
                return store
            },
        )

        let code = try await loader.incrementAndRenderHOTPCode(id: item.id.rawValue)

        #expect(code == nil)
        #expect(await store.incrementedIDs.isEmpty)
        #expect(opens.value == 0)
        #expect(loader.advancesHOTPInTheApp)
    }

    @Test(arguments: [VaultAccessMode.plain, .password, .unavailable])
    func advancesHOTPInTheApp_onlyWithTheDeviceKey(mode: VaultAccessMode) throws {
        let loader = try WidgetVaultLoader(
            appLockSettings: AppLockSettingsStore(userDefaults: .nonPersistent()),
            accessMode: { mode },
            makeStore: { _ in IncrementingFakeStore(items: []) },
        )

        #expect(!loader.advancesHOTPInTheApp)
    }

    /// The small widget's HOTP entry links to the app with the password off, and advances the counter itself
    /// otherwise.
    @Test(arguments: [VaultAccessMode.deviceKey, .plain])
    func providerTimeline_hotp_advancesInTheAppOnlyWithTheDeviceKey(mode: VaultAccessMode) async throws {
        let item = makeHOTPVaultItem(counter: 4)
        let loader = try WidgetVaultLoader(
            appLockSettings: AppLockSettingsStore(userDefaults: .nonPersistent()),
            accessMode: { mode },
            makeStore: { _ in IncrementingFakeStore(items: [item]) },
        )
        let entity = OTPWidgetItemEntity(id: item.id.rawValue, issuer: "issuer", accountName: "account")

        let timeline = await OTPWidgetProvider(loader: loader).makeTimeline(for: .init(item: entity))

        guard case let .hotp(hotp) = timeline.entries.first?.snapshot else {
            Issue.record("Expected a HOTP entry, got \(String(describing: timeline.entries.first?.snapshot))")
            return
        }
        #expect(hotp.advancesInTheApp == (mode == .deviceKey))
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

    /// A code with a killphrase is eligible like any other visible code (MANIFESTO C5).
    @Test
    func incrementAndRenderHOTPCode_killphraseItemIncrements() async throws {
        let item = makeHOTPVaultItem(counter: 1, killphrase: .init(salt: Data([1]), digest: Data([2])))
        let store = IncrementingFakeStore(items: [item])
        let loader = WidgetVaultLoader(store: store)

        let code = try await loader.incrementAndRenderHOTPCode(id: item.id.rawValue)

        #expect(code != nil)
        #expect(await store.incrementedIDs == [item.id])
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

    /// A code is rendered with its own period: at 120 seconds, a 60 second code is the RFC 4226 value for counter 2,
    /// not the value for counter 4 that a 30 second period would give.
    @Test
    func currentTOTPCode_usesTheCodesPeriod() async throws {
        let item = makeTOTPVaultItem(period: 60, data: rfcData())
        let loader = WidgetVaultLoader(store: IncrementingFakeStore(items: [item]))

        let code = try await loader.currentTOTPCode(id: item.id.rawValue, date: Date(timeIntervalSince1970: 120))

        #expect(code == "359152")
    }

    /// Both of the widget's entries show the code for their own 60 second period.
    @Test
    func providerTimeline_totp_usesTheCodesPeriod() async throws {
        let item = makeTOTPVaultItem(period: 60, data: rfcData())
        let loader = try WidgetVaultLoader(
            store: IncrementingFakeStore(items: [item]),
            appLockSettings: AppLockSettingsStore(userDefaults: .nonPersistent()),
        )
        let entity = OTPWidgetItemEntity(id: item.id.rawValue, issuer: "issuer", accountName: "account")

        let timeline = await OTPWidgetProvider(loader: loader).makeTimeline(for: .init(item: entity))

        let entries = timeline.entries.compactMap { entry -> OTPWidgetSnapshot.TOTP? in
            guard case let .totp(totp) = entry.snapshot else { return nil }
            return totp
        }
        #expect(entries.count == 2)
        for totp in entries {
            let periodStart = UInt64(totp.periodStart.timeIntervalSince1970)
            #expect(totp.periodEnd.timeIntervalSince(totp.periodStart) == 60)
            #expect(periodStart % 60 == 0)
            let expected = try HOTPAuthCode(counter: periodStart / 60, data: rfcData()).renderCode()
            #expect(totp.code == expected)
        }
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

/// The RFC 4226 test secret, whose codes for each counter are known.
private func rfcData() -> OTPAuthCodeData {
    .init(
        secret: .init(data: Data("12345678901234567890".utf8), format: .base32),
        accountName: "account",
        issuer: "Issuer",
    )
}

private func makeTOTPVaultItem(
    period: UInt64 = 30,
    data: OTPAuthCodeData = hotpData(),
    visibility: VaultItemVisibility = .always,
) -> VaultItem {
    makeItem(
        payload: .otpCode(.init(type: .totp(period: period), data: data)),
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
