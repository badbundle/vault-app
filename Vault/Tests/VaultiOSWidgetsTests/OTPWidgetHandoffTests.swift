import Foundation
import FoundationExtensions
import TestHelpers
import Testing
import VaultCore
import VaultFeed
import WidgetKit
@testable import VaultiOSWidgets

/// The Mac's widgets, which show only the codes the unlocked app hands them (G98). Their code is the iOS widgets', so
/// these run on both.
struct OTPWidgetHandoffTests {
    /// Partway through a 30-second period.
    private let now = Date(timeIntervalSince1970: 1_800_000_010)

    @Test
    func timeline_showsEachCodeInTurnThenLocked() async throws {
        let item = makeOTPVaultItem(issuer: "Issuer", accountName: "account")
        let sut = makeSUT()
        let handoff = WidgetCodeHandoff(items: [item], now: now, window: 60)
        try sut.store.publish(handoff)

        let timeline = await sut.provider.makeTimeline(for: .init(item: entity(for: item)), now: now)

        let codes = try #require(handoff.item(id: item.id.rawValue)).codes
        #expect(timeline.entries.map(\.date) == [now] + codes.dropFirst().map(\.start) + [handoff.expiresAt])
        #expect(timeline.entries.map(\.snapshot) == codes.map { code in
            .totp(.init(
                itemID: item.id.rawValue,
                issuer: "Issuer",
                accountName: "account",
                code: code.code,
                digits: 6,
                periodStart: code.start,
                periodEnd: code.end,
            ))
        } + [.locked])
        #expect(timeline.policy == .after(handoff.expiresAt))
    }

    /// While the app hands over no codes, which is whenever Vault's locked, the widget shows it locked.
    @Test
    func timeline_withNoHandoff_isLocked() async throws {
        let item = makeOTPVaultItem()
        let sut = makeSUT()

        let timeline = await sut.provider.makeTimeline(for: .init(item: entity(for: item)), now: now)

        #expect(timeline.entries.map(\.snapshot) == [.locked])
    }

    @Test
    func timeline_onceTheCodesAreTakenBack_isLocked() async throws {
        let item = makeOTPVaultItem()
        let sut = makeSUT()
        try sut.store.publish(WidgetCodeHandoff(items: [item], now: now))

        try sut.store.withdraw()
        let timeline = await sut.provider.makeTimeline(for: .init(item: entity(for: item)), now: now)

        #expect(timeline.entries.map(\.snapshot) == [.locked])
    }

    @Test
    func timeline_onceTheHandoffHasExpired_isLocked() async throws {
        let item = makeOTPVaultItem()
        let sut = makeSUT()
        let handoff = WidgetCodeHandoff(items: [item], now: now)
        try sut.store.publish(handoff)

        let timeline = await sut.provider.makeTimeline(for: .init(item: entity(for: item)), now: handoff.expiresAt)

        #expect(timeline.entries.map(\.snapshot) == [.locked])
    }

    /// A code that's gone, or that a widget may no longer show, looks the same as one that never was (manifesto C2),
    /// and the widget shows Vault locked once the codes run out.
    @Test
    func timeline_codeNotHandedOver_isUnavailableThenLocked() async throws {
        let sut = makeSUT()
        let handoff = WidgetCodeHandoff(items: [makeOTPVaultItem(lockState: .lockedWithNativeSecurity)], now: now)
        try sut.store.publish(handoff)
        let locked = OTPWidgetItemEntity(id: UUID(), issuer: "", accountName: "")

        let timeline = await sut.provider.makeTimeline(for: .init(item: locked), now: now)

        #expect(timeline.entries.map(\.snapshot) == [.unavailable, .locked])
        #expect(timeline.entries.last?.date == handoff.expiresAt)
    }

    /// The widget's settings list only the codes handed over, and none while Vault's locked.
    @Test
    func entityQuery_listsOnlyTheCodesHandedOver() async throws {
        let shown = makeOTPVaultItem(issuer: "Shown", accountName: "account")
        let hidden = makeOTPVaultItem(visibility: .onlySearch)
        let sut = makeSUT()
        try sut.store.publish(WidgetCodeHandoff(items: [shown, hidden], now: Date()))

        let suggested = try await sut.query.suggestedEntities()
        let found = try await sut.query.entities(for: [shown.id.rawValue, hidden.id.rawValue])

        #expect(suggested == [OTPWidgetItemEntity(id: shown.id.rawValue, issuer: "Shown", accountName: "account")])
        #expect(found == suggested)
    }

    @Test
    func entityQuery_withNoHandoff_listsNothing() async throws {
        let sut = makeSUT()

        #expect(try await sut.query.suggestedEntities().isEmpty)
        #expect(try await sut.query.entities(for: [UUID()]).isEmpty)
        #expect(await sut.query.defaultResult() == nil)
    }

    @Test
    func copy_isTheCodeShowingNow() async throws {
        let item = makeOTPVaultItem()
        let sut = makeSUT()
        let handoff = WidgetCodeHandoff(items: [item], now: now)
        try sut.store.publish(handoff)
        let source = OTPWidgetSource.handoff(sut.store)

        let code = try await source.currentTOTPCode(itemID: item.id.rawValue, now: now)

        #expect(code == handoff.code(itemID: item.id.rawValue, at: now))
        #expect(code != nil)
    }

    @Test
    func copy_onceTheCodesAreTakenBack_copiesNothing() async throws {
        let item = makeOTPVaultItem()
        let sut = makeSUT()
        try sut.store.publish(WidgetCodeHandoff(items: [item], now: now))
        try sut.store.withdraw()

        let code = try await OTPWidgetSource.handoff(sut.store).currentTOTPCode(itemID: item.id.rawValue, now: now)

        #expect(code == nil)
    }

    /// The Mac's widgets are never given a counter-based code, so never advance one.
    @Test
    func nextCounterBasedCode_isNeverFromTheHandoff() async throws {
        let sut = makeSUT()

        #expect(try await OTPWidgetSource.handoff(sut.store).incrementAndRenderHOTPCode(itemID: UUID()) == nil)
    }
}

// MARK: - Helpers

extension OTPWidgetHandoffTests {
    private struct SUT {
        var store: WidgetCodeHandoffStore
        var provider: OTPWidgetProvider
        var query: OTPWidgetItemEntityQuery
    }

    private func makeSUT() -> SUT {
        let store = WidgetCodeHandoffStore(keychain: InMemoryKeychain())
        return SUT(
            store: store,
            provider: OTPWidgetProvider(handoff: store),
            query: OTPWidgetItemEntityQuery(handoff: store),
        )
    }

    private func entity(for item: VaultItem) -> OTPWidgetItemEntity {
        OTPWidgetItemEntity(id: item.id.rawValue, issuer: "", accountName: "")
    }

    private func makeOTPVaultItem(
        issuer: String = "",
        accountName: String = "",
        visibility: VaultItemVisibility = .always,
        lockState: VaultItemLockState = .notLocked,
    ) -> VaultItem {
        let date = Date(timeIntervalSince1970: 0)
        return VaultItem(
            metadata: .init(
                id: .new(),
                created: date,
                updated: date,
                relativeOrder: 0,
                userDescription: "",
                tags: [],
                visibility: visibility,
                searchableLevel: .full,
                searchPassphrase: nil,
                killphrase: nil,
                lockState: lockState,
                color: nil,
                showInQuickType: true,
                previewMode: .titleAndFirstLine,
            ),
            item: .otpCode(.init(
                type: .totp(period: 30),
                data: .init(
                    secret: .init(data: Data(repeating: 1, count: 20), format: .base32),
                    accountName: accountName,
                    issuer: issuer,
                ),
            )),
        )
    }
}

/// One of the widgets' keychain items, in memory.
final class InMemoryKeychain: WidgetKeychainStoring {
    private let data = SharedMutex<Data?>(nil)

    func read() throws -> Data? {
        data.get { $0 }
    }

    func save(_ newData: Data) throws {
        data.modify { $0 = newData }
    }

    func remove() throws {
        data.modify { $0 = nil }
    }
}
