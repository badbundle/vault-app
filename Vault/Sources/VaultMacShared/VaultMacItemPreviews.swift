import FoundationExtensions
import SwiftUI
import VaultCore
import VaultFeed

/// Where the list and an item's page get the live parts of a code: its digits, its timer, and its counter's Next
/// Code. The app's come from the shared repositories, which forget everything when Vault locks; snapshot tests give
/// fixed ones.
@MainActor
public struct VaultMacItemPreviews {
    public var totp: (VaultItem.Metadata, TOTPAuthCode) -> OTPCodePreviewViewModel
    public var hotp: (VaultItem.Metadata, HOTPAuthCode) -> OTPCodePreviewViewModel
    /// The countdown shared by every code with this period.
    public var timer: (UInt64) -> OTPCodeTimerPeriodState?
    /// Advances a counter-based code to its next code.
    public var incrementer: (Identifier<VaultItem>, HOTPAuthCode) -> OTPCodeIncrementerViewModel?

    public init(
        totp: @escaping (VaultItem.Metadata, TOTPAuthCode) -> OTPCodePreviewViewModel,
        hotp: @escaping (VaultItem.Metadata, HOTPAuthCode) -> OTPCodePreviewViewModel,
        timer: @escaping (UInt64) -> OTPCodeTimerPeriodState?,
        incrementer: @escaping (Identifier<VaultItem>, HOTPAuthCode) -> OTPCodeIncrementerViewModel?,
    ) {
        self.totp = totp
        self.hotp = hotp
        self.timer = timer
        self.incrementer = incrementer
    }

    /// The code's view model, if the item is a code.
    public func code(for item: VaultItem) -> OTPCodePreviewViewModel? {
        guard case let .otpCode(code) = item.item else { return nil }
        return switch code.type {
        case let .totp(period): totp(item.metadata, .init(period: period, data: code.data))
        case let .hotp(counter): hotp(item.metadata, .init(counter: counter, data: code.data))
        }
    }

    /// The countdown for the item, if it's a time-based code.
    public func timer(for item: VaultItem) -> OTPCodeTimerPeriodState? {
        guard case let .otpCode(code) = item.item, case let .totp(period) = code.type else { return nil }
        return timer(period)
    }
}

extension EnvironmentValues {
    @Entry public var vaultMacItemPreviews: VaultMacItemPreviews?
}
