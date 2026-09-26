import SwiftUI
import VaultiOSShared
import WidgetKit

/// `accessoryCircular` (lock-screen ring) layout. Too small for the chunked
/// code in a readable size; we show the seconds remaining inside the ring
/// (TOTP), a key glyph (HOTP) or a padlock (unavailable / locked) and let the user open the app
/// to read the actual code.
struct OTPWidgetAccessoryCircularView: View {
    let snapshot: OTPWidgetSnapshot

    var body: some View {
        ZStack {
            switch snapshot {
            case let .totp(state):
                ProgressView(
                    timerInterval: state.periodStart ... state.periodEnd,
                    countsDown: true,
                ) {
                    Text(state.code.suffix(3))
                        .font(.system(.caption2, design: .monospaced).weight(.semibold))
                } currentValueLabel: {
                    Text(state.code.suffix(3))
                        .font(.system(.caption2, design: .monospaced).weight(.semibold))
                }
                .progressViewStyle(.circular)
            case .hotp:
                Image(systemName: "key.horizontal.fill")
                    .font(.title3)
            case .unavailable, .locked, .placeholder:
                Image(systemName: "lock.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .widgetURL(deepLinkURL)
    }

    private var deepLinkURL: URL? {
        switch snapshot {
        case let .hotp(state): WidgetDeepLink.hotpIncrement(itemID: state.itemID)
        case .totp, .unavailable, .locked, .placeholder: nil
        }
    }
}
