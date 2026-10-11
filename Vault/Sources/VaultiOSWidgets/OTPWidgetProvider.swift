import AppIntents
import Foundation
import VaultCore
import VaultFeed
import WidgetKit

/// Builds widget timeline entries from the user's selected OTP item.
///
/// TOTP entries advance at period boundaries — we emit the current period's
/// entry plus the next period's entry so the in-progress and rolled-over
/// codes are both ready without a round trip. HOTP entries are static
/// snapshots of the last persisted counter value; the app must reload the
/// timeline after incrementing.
///
/// Items that have become ineligible since the user configured the widget
/// (locked, hidden, killphrased, etc.) render as `.unavailable` — the same
/// state shown for deleted or missing items, so a viewer cannot distinguish
/// the two (manifesto C2).
///
/// While the app lock is on, or the vault is encrypted with the App Lock
/// Password, every widget renders as `.locked`, whatever it was set up to
/// show.
///
/// On the Mac, the widget shows only the codes the unlocked app hands it
/// (`WidgetCodeHandoff`): one entry for each period until they run out, then
/// `.locked`. While the app hands over none, it renders as `.locked`.
public struct OTPWidgetProvider: AppIntentTimelineProvider {
    public typealias Entry = OTPWidgetEntry
    public typealias Intent = OTPWidgetIntent

    /// How long an unavailable entry remains in the timeline before the
    /// system asks for a fresh one. Recovers from transient store-open
    /// failures without spinning the CPU.
    private static let unavailableRefreshInterval: TimeInterval = 15 * 60

    private let source: OTPWidgetSource

    /// This platform's widgets: the vault on iOS, the codes the app hands over on the Mac.
    public init() {
        source = .platform
    }

    public init(loader: WidgetVaultLoader) {
        source = .vault(loader)
    }

    public init(handoff: WidgetCodeHandoffStore) {
        source = .handoff(handoff)
    }

    public func placeholder(in _: Context) -> OTPWidgetEntry {
        OTPWidgetEntry(date: Date(), snapshot: .placeholder)
    }

    public func snapshot(for _: OTPWidgetIntent, in _: Context) async -> OTPWidgetEntry {
        // Snapshot is used for the widget gallery, transitions, and previews.
        // Never leak real codes here — placeholder is sufficient and safer.
        OTPWidgetEntry(date: Date(), snapshot: .placeholder)
    }

    public func timeline(
        for configuration: OTPWidgetIntent,
        in _: Context,
    ) async -> Timeline<OTPWidgetEntry> {
        await makeTimeline(for: configuration)
    }

    func makeTimeline(for configuration: OTPWidgetIntent, now: Date = Date()) async -> Timeline<OTPWidgetEntry> {
        switch source {
        case let .vault(loader):
            await vaultTimeline(for: configuration, loader: loader)
        case let .handoff(store):
            handoffTimeline(for: configuration, handoff: store.current(at: now), now: now)
        }
    }

    private func vaultTimeline(
        for configuration: OTPWidgetIntent,
        loader: WidgetVaultLoader,
    ) async -> Timeline<OTPWidgetEntry> {
        // Checked before anything else, so no item is read. The app reloads
        // every timeline when the lock or the password is turned on or off.
        if loader.isLocked {
            return lockedTimeline()
        }

        guard let entityID = configuration.item?.id else {
            return unavailableTimeline()
        }

        guard let item = try? await loader.eligibleItem(id: entityID),
              case let .otpCode(otp) = item.item
        else {
            return unavailableTimeline()
        }

        switch otp.type {
        case let .totp(period):
            return totpTimeline(itemID: item.id.rawValue, otp: otp, period: period)
        case let .hotp(counter):
            return hotpTimeline(
                itemID: item.id.rawValue,
                otp: otp,
                counter: counter,
                advancesInTheApp: loader.advancesHOTPInTheApp,
            )
        }
    }

    // MARK: - TOTP

    private func totpTimeline(
        itemID: UUID,
        otp: OTPAuthCode,
        period: UInt64,
    ) -> Timeline<OTPWidgetEntry> {
        let now = Date()
        let nowEpoch = now.timeIntervalSince1970
        let currentState = OTPCodeTimerState(currentTime: nowEpoch, period: period)
        let nextState = currentState.offset(time: Double(period))

        let entries: [OTPWidgetEntry] = [
            makeTOTPEntry(at: now, itemID: itemID, otp: otp, period: period, state: currentState),
            makeTOTPEntry(
                at: Date(timeIntervalSince1970: currentState.endTime),
                itemID: itemID,
                otp: otp,
                period: period,
                state: nextState,
            ),
        ].compactMap(\.self)

        if entries.isEmpty {
            return unavailableTimeline()
        }
        return Timeline(
            entries: entries,
            policy: .after(Date(timeIntervalSince1970: nextState.endTime)),
        )
    }

    private func makeTOTPEntry(
        at date: Date,
        itemID: UUID,
        otp: OTPAuthCode,
        period: UInt64,
        state: OTPCodeTimerState,
    ) -> OTPWidgetEntry? {
        let totp = TOTPAuthCode(period: period, data: otp.data)
        let epochSeconds = UInt64(state.startTime)
        guard let rendered = try? totp.renderCode(epochSeconds: epochSeconds) else {
            return nil
        }
        return OTPWidgetEntry(
            date: date,
            snapshot: .totp(.init(
                itemID: itemID,
                issuer: otp.data.issuer,
                accountName: otp.data.accountName,
                code: rendered,
                digits: Int(otp.data.digits.value),
                periodStart: Date(timeIntervalSince1970: state.startTime),
                periodEnd: Date(timeIntervalSince1970: state.endTime),
            )),
        )
    }

    // MARK: - HOTP

    private func hotpTimeline(
        itemID: UUID,
        otp: OTPAuthCode,
        counter _: UInt64,
        advancesInTheApp: Bool,
    ) -> Timeline<OTPWidgetEntry> {
        let entry = OTPWidgetEntry(
            date: Date(),
            snapshot: .hotp(.init(
                itemID: itemID,
                issuer: otp.data.issuer,
                accountName: otp.data.accountName,
                digits: Int(otp.data.digits.value),
                advancesInTheApp: advancesInTheApp,
            )),
        )
        // HOTP only refreshes when the app pings `WidgetCenter.reloadAllTimelines()`
        // after the user increments the counter via deep link.
        return Timeline(entries: [entry], policy: .never)
    }

    // MARK: - Handed over by the Mac app

    /// A widget on the Mac: each of the item's codes the app handed over, in turn, until they run out, and then
    /// `.locked`, so the widget never shows a code once the app stops handing them over, even if it isn't reloaded.
    /// The app reloads it whenever it hands codes over or takes them back.
    private func handoffTimeline(
        for configuration: OTPWidgetIntent,
        handoff: WidgetCodeHandoff?,
        now: Date,
    ) -> Timeline<OTPWidgetEntry> {
        guard let handoff else {
            return lockedTimeline()
        }
        guard let itemID = configuration.item?.id, let item = handoff.item(id: itemID) else {
            // Missing, or no longer one a widget may show, which look the same (manifesto C2).
            return Timeline(
                entries: [
                    OTPWidgetEntry(date: now, snapshot: .unavailable),
                    OTPWidgetEntry(date: handoff.expiresAt, snapshot: .locked),
                ],
                policy: .after(handoff.expiresAt),
            )
        }
        let codes = item.codes.filter { $0.end > now && $0.start < handoff.expiresAt }
        guard let last = codes.last else {
            return lockedTimeline()
        }
        let entries = codes.map { code in
            OTPWidgetEntry(
                date: max(code.start, now),
                snapshot: .totp(.init(
                    itemID: item.id,
                    issuer: item.issuer,
                    accountName: item.accountName,
                    code: code.code,
                    digits: item.digits,
                    periodStart: code.start,
                    periodEnd: code.end,
                )),
            )
        }
        return Timeline(
            entries: entries + [OTPWidgetEntry(date: min(handoff.expiresAt, last.end), snapshot: .locked)],
            policy: .after(handoff.expiresAt),
        )
    }

    // MARK: - Unavailable

    private func unavailableTimeline() -> Timeline<OTPWidgetEntry> {
        let entry = OTPWidgetEntry(date: Date(), snapshot: .unavailable)
        return Timeline(
            entries: [entry],
            policy: .after(Date().addingTimeInterval(Self.unavailableRefreshInterval)),
        )
    }

    // MARK: - Locked

    private func lockedTimeline() -> Timeline<OTPWidgetEntry> {
        let entry = OTPWidgetEntry(date: Date(), snapshot: .locked)
        return Timeline(
            entries: [entry],
            policy: .after(Date().addingTimeInterval(Self.unavailableRefreshInterval)),
        )
    }
}
