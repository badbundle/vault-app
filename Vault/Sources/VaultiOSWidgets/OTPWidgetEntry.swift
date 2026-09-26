import Foundation
import WidgetKit

/// Single timeline entry for the OTP widget. The `snapshot` carries
/// everything the view needs to render at a point in time; entries are
/// otherwise opaque to callers.
public struct OTPWidgetEntry: TimelineEntry, Sendable {
    public var date: Date
    public var snapshot: OTPWidgetSnapshot

    public init(date: Date, snapshot: OTPWidgetSnapshot) {
        self.date = date
        self.snapshot = snapshot
    }
}

/// Renderable state for the widget. Modeled as an enum so the "unavailable"
/// and "placeholder" states are first-class — a deleted or newly-hidden item
/// must render identically to one that never existed, so views cannot
/// distinguish them (manifesto C2).
public enum OTPWidgetSnapshot: Sendable, Equatable {
    /// Pre-data placeholder used by `placeholder(in:)` and snapshot calls.
    /// Should never reveal real item content.
    case placeholder

    /// Item is missing, ineligible, or could not be loaded. Rendered the
    /// same way regardless of cause.
    case unavailable

    /// The app lock is on, so the widget shows nothing of the vault: no code,
    /// and not which item it's set up for.
    case locked

    /// Live TOTP code valid until `periodEnd`. Progress bars use the
    /// `[periodStart, periodEnd]` interval directly.
    case totp(TOTP)

    /// HOTP item metadata. The code is intentionally not stored in the
    /// snapshot because the persisted counter may already be stale.
    case hotp(HOTP)

    public struct TOTP: Sendable, Equatable {
        public var itemID: UUID
        public var issuer: String
        public var accountName: String
        public var code: String
        public var digits: Int
        public var periodStart: Date
        public var periodEnd: Date

        public init(
            itemID: UUID,
            issuer: String,
            accountName: String,
            code: String,
            digits: Int,
            periodStart: Date,
            periodEnd: Date,
        ) {
            self.itemID = itemID
            self.issuer = issuer
            self.accountName = accountName
            self.code = code
            self.digits = digits
            self.periodStart = periodStart
            self.periodEnd = periodEnd
        }
    }

    public struct HOTP: Sendable, Equatable {
        public var itemID: UUID
        public var issuer: String
        public var accountName: String
        public var digits: Int

        public init(
            itemID: UUID,
            issuer: String,
            accountName: String,
            digits: Int,
        ) {
            self.itemID = itemID
            self.issuer = issuer
            self.accountName = accountName
            self.digits = digits
        }
    }
}
