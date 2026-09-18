import SwiftUI
import VaultFeed
import VaultiOSShared
import WidgetKit

/// `accessoryRectangular` (lock-screen rectangular) layout. Tight space —
/// issuer caption, chunked digits, thin progress bar.
struct OTPWidgetAccessoryRectangularView: View {
    let snapshot: OTPWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(issuerLine)
                .font(.caption2)
                .lineLimit(1)

            OTPCodeTextView(codeState: codeState, scaledDigitSpacing: 3)
                .font(.system(.title3, design: .monospaced))
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            timerBar
                .frame(height: 3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(deepLinkURL)
    }

    @ViewBuilder
    private var timerBar: some View {
        switch snapshot {
        case let .totp(state):
            ProgressView(
                timerInterval: state.periodStart ... state.periodEnd,
                countsDown: true,
                label: { EmptyView() },
                currentValueLabel: { EmptyView() },
            )
            .progressViewStyle(.linear)
        case .hotp, .unavailable, .placeholder:
            Color(.quaternarySystemFill).clipShape(Capsule())
        }
    }

    private var codeState: OTPCodeState {
        switch snapshot {
        case let .totp(state): .visible(state.code)
        // The stored counter may already be stale, so the widget shows
        // masked digits until the user advances it in the app.
        case let .hotp(state): .locked(code: String(repeating: "0", count: state.digits))
        case .unavailable, .placeholder: .notReady
        }
    }

    private var issuerLine: String {
        switch snapshot {
        case let .totp(state):
            state.issuer.isEmpty ? state.accountName : state.issuer
        case let .hotp(state):
            state.issuer.isEmpty ? state.accountName : state.issuer
        case .unavailable: "Unavailable"
        case .placeholder: "—"
        }
    }

    private var deepLinkURL: URL? {
        switch snapshot {
        case let .hotp(state): WidgetDeepLink.hotpIncrement(itemID: state.itemID)
        case .totp, .unavailable, .placeholder: nil
        }
    }
}
