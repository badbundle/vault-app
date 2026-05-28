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
public struct OTPWidgetProvider: AppIntentTimelineProvider {
    public typealias Entry = OTPWidgetEntry
    public typealias Intent = OTPWidgetIntent

    /// How long an unavailable entry remains in the timeline before the
    /// system asks for a fresh one. Recovers from transient store-open
    /// failures without spinning the CPU.
    private static let unavailableRefreshInterval: TimeInterval = 15 * 60

    private let loader: WidgetVaultLoader

    public init(loader: WidgetVaultLoader = .shared) {
        self.loader = loader
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

    func makeTimeline(for configuration: OTPWidgetIntent) async -> Timeline<OTPWidgetEntry> {
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
            return hotpTimeline(itemID: item.id.rawValue, otp: otp, counter: counter)
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
    ) -> Timeline<OTPWidgetEntry> {
        let entry = OTPWidgetEntry(
            date: Date(),
            snapshot: .hotp(.init(
                itemID: itemID,
                issuer: otp.data.issuer,
                accountName: otp.data.accountName,
                digits: Int(otp.data.digits.value),
            )),
        )
        // HOTP only refreshes when the app pings `WidgetCenter.reloadAllTimelines()`
        // after the user increments the counter via deep link.
        return Timeline(entries: [entry], policy: .never)
    }

    // MARK: - Unavailable

    private func unavailableTimeline() -> Timeline<OTPWidgetEntry> {
        let entry = OTPWidgetEntry(date: Date(), snapshot: .unavailable)
        return Timeline(
            entries: [entry],
            policy: .after(Date().addingTimeInterval(Self.unavailableRefreshInterval)),
        )
    }
}
