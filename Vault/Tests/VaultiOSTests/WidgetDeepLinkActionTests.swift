import Foundation
import Testing
import VaultFeed
import VaultiOSShared
@testable import VaultiOS

/// What the app does with a link from a widget.
struct WidgetDeepLinkActionTests {
    /// As widgets do while the vault opens without the password: plain, or with the device key.
    @Test(arguments: [VaultAccessMode.plain, .deviceKey])
    func incrementHOTP_noPasswordNeeded_isFollowed(accessMode: VaultAccessMode) {
        #expect(WidgetDeepLink.Action.incrementHOTP(itemID: UUID()).isAllowed(in: accessMode))
    }

    /// A widget never offers it while only the password opens the vault, and a link left from before doesn't either.
    @Test(arguments: [VaultAccessMode.password, .unavailable])
    func incrementHOTP_passwordNeeded_isIgnored(accessMode: VaultAccessMode) {
        #expect(!WidgetDeepLink.Action.incrementHOTP(itemID: UUID()).isAllowed(in: accessMode))
    }

    /// Opening an item still waits for the app to be unlocked, with the password if it's on, like anything else.
    @Test(arguments: [VaultAccessMode.plain, .deviceKey, .password, .unavailable])
    func openItemDetail_isFollowed(accessMode: VaultAccessMode) {
        #expect(WidgetDeepLink.Action.openItemDetail(itemID: UUID()).isAllowed(in: accessMode))
    }
}
