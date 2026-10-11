import Foundation
import VaultCore

/// The codes the unlocked Mac app hands its widgets: each code a widget may show, worked out by the app for the next
/// few minutes (`window`), with the site and account that go with it (docs/mac-app.md, "Widgets").
///
/// It never holds a secret. The widget extension never opens the vault, which only the App Lock Password does on the
/// Mac (G33), and has nothing to work a code out with: it can only show the codes it's given, until they run out.
///
/// Only codes `VaultItemWidgetEligibility` allows, so never a locked or hidden one (G45), and only time-based ones: a
/// counter-based code stays usable until it's used, so it's never worked out ahead.
public struct WidgetCodeHandoff: Codable, Equatable, Sendable {
    /// Which handoff this is: each one the app makes is new.
    public var id: UUID
    /// When the codes run out. A widget shows none of them from then on, whatever it was given.
    public var expiresAt: Date
    public var items: [Item]

    public init(id: UUID, expiresAt: Date, items: [Item]) {
        self.id = id
        self.expiresAt = expiresAt
        self.items = items
    }

    /// A code a widget may show.
    public struct Item: Codable, Equatable, Sendable, Identifiable {
        /// The vault item's ID, which a widget is set up with.
        public var id: UUID
        public var issuer: String
        public var accountName: String
        public var digits: Int
        /// Each code, in order, from the one showing when the handoff was made to the one showing when it expires.
        public var codes: [Code]

        public init(id: UUID, issuer: String, accountName: String, digits: Int, codes: [Code]) {
            self.id = id
            self.issuer = issuer
            self.accountName = accountName
            self.digits = digits
            self.codes = codes
        }
    }

    /// One period's code.
    public struct Code: Codable, Equatable, Sendable {
        public var code: String
        /// When its period starts.
        public var start: Date
        /// When its period ends, and the next code's starts.
        public var end: Date

        public init(code: String, start: Date, end: Date) {
            self.code = code
            self.start = start
            self.end = end
        }
    }
}

extension WidgetCodeHandoff {
    /// How far ahead the app works codes out. It's the longest a widget can go on showing codes once Vault locks, if
    /// macOS doesn't reload it when asked to, or once Vault stops without locking, as when it crashes.
    public static let window: TimeInterval = 5 * 60

    /// The most codes worked out for one item, in case its period is very short.
    static let maximumCodesPerItem = 64

    /// Works out, from `items`, the codes widgets may show from `now` until `window` has passed.
    public init(items: [VaultItem], now: Date, window: TimeInterval = Self.window, id: UUID = UUID()) {
        let expiresAt = now.addingTimeInterval(window)
        self.init(
            id: id,
            expiresAt: expiresAt,
            items: items.compactMap { Self.item(from: $0, now: now, expiresAt: expiresAt) },
        )
    }

    /// The item's codes, or `nil` if a widget mustn't show it, or one of its codes can't be worked out.
    private static func item(from vaultItem: VaultItem, now: Date, expiresAt: Date) -> Item? {
        guard VaultItemWidgetEligibility.isEligible(vaultItem),
              case let .otpCode(otp) = vaultItem.item,
              case let .totp(period) = otp.type
        else {
            return nil
        }
        let totp = TOTPAuthCode(period: period, data: otp.data)
        var state = OTPCodeTimerState(currentTime: now.timeIntervalSince1970, period: period)
        var codes = [Code]()
        while state.startTime < expiresAt.timeIntervalSince1970, codes.count < maximumCodesPerItem {
            guard let code = try? totp.renderCode(epochSeconds: UInt64(state.startTime)) else { return nil }
            codes.append(Code(
                code: code,
                start: Date(timeIntervalSince1970: state.startTime),
                end: Date(timeIntervalSince1970: state.endTime),
            ))
            state = state.offset(time: state.totalTime)
        }
        return Item(
            id: vaultItem.id.rawValue,
            issuer: otp.data.issuer,
            accountName: otp.data.accountName,
            digits: Int(otp.data.digits.value),
            codes: codes,
        )
    }

    /// The item with this ID, if a widget may show it.
    public func item(id: UUID) -> Item? {
        items.first { $0.id == id }
    }

    /// The item's code at `date`, or `nil` if there's none then: the handoff has expired, or never had one for then.
    public func code(itemID: UUID, at date: Date) -> String? {
        guard date < expiresAt else { return nil }
        return item(id: itemID)?.codes.first { $0.start <= date && date < $0.end }?.code
    }
}
