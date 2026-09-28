import Foundation
import Testing
import VaultFeed
@testable import VaultiOS

struct VaultRootPlainStoreTests {
    /// Only the app sets aside a plain store it can't open and starts again.
    @Test
    func plainStoreRecoveryMode_inTheApp_recoversTheStore() {
        #expect(VaultRoot.plainStoreRecoveryMode(isAppExtension: false) == .recoverExistingStore)
    }

    /// An extension only opens the plain store, as the widgets do, and leaves one it can't open for the app.
    @Test
    func plainStoreRecoveryMode_inAnExtension_onlyOpens() {
        #expect(VaultRoot.plainStoreRecoveryMode(isAppExtension: true) == .openOnly)
    }
}
