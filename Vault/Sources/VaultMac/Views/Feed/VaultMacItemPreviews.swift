import FoundationExtensions
import SwiftUI
import VaultCore
import VaultFeed

/// Where the list and an item's page get the live parts of a code: its digits, its timer, and its counter's Next
/// Code. The app's come from the shared repositories, which forget everything when Vault locks; snapshot tests give
/// fixed ones.
@MainActor
struct VaultMacItemPreviews {
    var totp: (VaultItem.Metadata, TOTPAuthCode) -> OTPCodePreviewViewModel
    var hotp: (VaultItem.Metadata, HOTPAuthCode) -> OTPCodePreviewViewModel
    /// The countdown shared by every code with this period.
    var timer: (UInt64) -> OTPCodeTimerPeriodState?
    /// Advances a counter-based code to its next code.
    var incrementer: (Identifier<VaultItem>, HOTPAuthCode) -> OTPCodeIncrementerViewModel?

    /// The code's view model, if the item is a code.
    func code(for item: VaultItem) -> OTPCodePreviewViewModel? {
        guard case let .otpCode(code) = item.item else { return nil }
        return switch code.type {
        case let .totp(period): totp(item.metadata, .init(period: period, data: code.data))
        case let .hotp(counter): hotp(item.metadata, .init(counter: counter, data: code.data))
        }
    }

    /// The countdown for the item, if it's a time-based code.
    func timer(for item: VaultItem) -> OTPCodeTimerPeriodState? {
        guard case let .otpCode(code) = item.item, case let .totp(period) = code.type else { return nil }
        return timer(period)
    }

    static var live: VaultMacItemPreviews {
        VaultMacItemPreviews(
            totp: { VaultMacRoot.totpPreviewRepository.previewViewModel(metadata: $0, code: $1) },
            hotp: { VaultMacRoot.hotpPreviewRepository.previewViewModel(metadata: $0, code: $1) },
            timer: { VaultMacRoot.totpPreviewRepository.timerPeriodState(period: $0) },
            incrementer: { VaultMacRoot.hotpPreviewRepository.incrementerViewModel(id: $0, code: $1) },
        )
    }
}

extension EnvironmentValues {
    @Entry var vaultMacItemPreviews: VaultMacItemPreviews?
    /// Copies an item's text: Vault's clipboard, after authenticating for a locked item.
    @Entry var vaultMacCopy: VaultMacCopyAction?
}

/// Copies an item's text, and says whether it did.
@MainActor
struct VaultMacCopyAction {
    var perform: @MainActor (VaultTextCopyAction) async -> Bool

    func callAsFunction(_ action: VaultTextCopyAction) async -> Bool {
        await perform(action)
    }
}
