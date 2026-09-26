import AppIntents
import SwiftUI
import VaultFeed
import VaultiOSShared
import WidgetKit

/// `systemSmall` layout. Mirrors `TOTPCodePreviewView` from the in-app
/// preview tile — icon top-left, issuer/account stack, large monospaced
/// chunked digits, horizontal progress bar at the bottom.
///
/// This is the only family with in-widget actions. The lock-screen accessory
/// families stay non-interactive on purpose: their buttons would be reachable
/// on a locked device, and advancing an HOTP counter is irreversible.
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
    }

    // MARK: - Pieces

    private var icon: some View {
        Image(systemName: snapshot == .locked ? "lock.fill" : "key.horizontal.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    /// Tapping the labels opens the item in the app. The code itself carries
    /// the action, so this stays the route to the full detail screen.
    @ViewBuilder
    private var labelsStack: some View {
        let content = VStack(alignment: .leading, spacing: 2) {
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

        switch snapshot {
        case let .totp(state):
            Link(destination: WidgetDeepLink.openItemDetail(itemID: state.itemID)) {
                content
            }
        case let .hotp(state):
            Link(destination: WidgetDeepLink.openItemDetail(itemID: state.itemID)) {
                content
            }
        case .unavailable, .locked, .placeholder:
            content
        }
    }

    @ViewBuilder
    private var codeSection: some View {
        let content = OTPCodeTextView(codeState: codeState)
            .font(.system(.largeTitle, design: .monospaced))
            .fontWeight(.heavy)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)

        switch snapshot {
        case let .totp(state):
            Button(intent: CopyTOTPCodeIntent(itemID: state.itemID)) {
                content
            }
            .buttonStyle(.plain)
        case let .hotp(state):
            Button(intent: IncrementAndCopyHOTPCodeIntent(itemID: state.itemID)) {
                content
            }
            .buttonStyle(.plain)
        case .unavailable, .locked, .placeholder:
            content
        }
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
        case .hotp, .unavailable, .locked, .placeholder:
            Color(.quaternarySystemFill)
        }
    }

    // MARK: - Snapshot accessors

    private var codeState: OTPCodeState {
        switch snapshot {
        case let .totp(state): .visible(state.code)
        // The persisted counter may already be stale, so the widget masks the
        // digits until the user taps to advance it.
        case let .hotp(state): .locked(code: String(repeating: "0", count: state.digits))
        case .unavailable, .locked, .placeholder: .notReady
        }
    }

    private var displayIssuer: String {
        switch snapshot {
        case let .totp(state): state.issuer.isEmpty ? state.accountName : state.issuer
        case let .hotp(state): state.issuer.isEmpty ? state.accountName : state.issuer
        case .unavailable: "Unavailable"
        case .locked: "Vault Locked"
        case .placeholder: "—"
        }
    }

    private var displayAccount: String {
        switch snapshot {
        case let .totp(state): state.accountName
        case let .hotp(state): state.accountName
        case .unavailable: "Open Vault to set up"
        case .locked: "Open Vault to see this code"
        case .placeholder: ""
        }
    }
}
