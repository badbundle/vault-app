import SwiftUI
import VaultFeed
import VaultiOSShared
import WidgetKit

/// `systemSmall` layout. Mirrors `TOTPCodePreviewView` from the in-app
/// preview tile — icon top-left, issuer/account stack, large monospaced
/// chunked digits, horizontal progress bar at the bottom.
struct OTPWidgetSmallView: View {
    let snapshot: OTPWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            icon
                .padding(.bottom, 8)

            labelsStack

            codeSection
                .padding(.vertical, 12)

            Spacer(minLength: 0)

            timerBar
                .frame(height: 12)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(deepLinkURL)
    }

    // MARK: - Pieces

    private var icon: some View {
        Image(systemName: "key.horizontal.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private var labelsStack: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(displayIssuer)
                .font(.title3.bold())
                .minimumScaleFactor(0.7)
                .allowsTightening(true)
                .foregroundStyle(.primary)
                .lineLimit(2)

            Text(displayAccount)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var codeSection: some View {
        OTPCodeTextView(codeState: codeState)
            .font(.system(.largeTitle, design: .monospaced))
            .fontWeight(.heavy)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
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
            .tint(.accentColor)
        case .hotp, .unavailable, .placeholder:
            Color.gray.opacity(0.3)
        }
    }

    // MARK: - Snapshot accessors

    private var codeState: OTPCodeState {
        switch snapshot {
        case let .totp(state): .visible(state.code)
        case let .hotp(state): .visible(state.code)
        case .unavailable, .placeholder: .notReady
        }
    }

    private var displayIssuer: String {
        switch snapshot {
        case let .totp(state): state.issuer.isEmpty ? state.accountName : state.issuer
        case let .hotp(state): state.issuer.isEmpty ? state.accountName : state.issuer
        case .unavailable: "Unavailable"
        case .placeholder: "—"
        }
    }

    private var displayAccount: String {
        switch snapshot {
        case let .totp(state): state.accountName
        case let .hotp(state): state.accountName
        case .unavailable: "Open Vault to set up"
        case .placeholder: ""
        }
    }

    private var deepLinkURL: URL? {
        switch snapshot {
        case let .hotp(state): WidgetDeepLink.hotpIncrement(itemID: state.itemID)
        case .totp, .unavailable, .placeholder: nil
        }
    }
}
