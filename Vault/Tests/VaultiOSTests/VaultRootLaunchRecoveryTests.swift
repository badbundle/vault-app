import Foundation
import Testing
import VaultFeed
@testable import VaultiOS

/// What the failure screen says when launch recovery (`VaultStorageRecovery.recoverAtLaunch()`) couldn't work out how
/// the vault is stored. Recovery's own results are in `VaultStorageRecoveryTests`, and each reason's screen in
/// `VaultStoreFailureViewSnapshotTests`.
struct VaultRootLaunchRecoveryTests {
    @Test(arguments: [
        (VaultStorageRecovery.Failure.deviceKeyMissing, VaultStoreFailureView.Reason.deviceKeyMissing),
        (.vaultMissing, .vaultMissing),
        (.encryptedFileWithoutPlainStore, .storeUnreadable),
        (.plainStoreWithoutEncryptedFile, .storeUnreadable),
        (.encryptedFileMissing, .storeUnreadable),
        (.fileUnreadableWhileLocked, .storeUnreadable),
    ])
    func failureReason_forEachRecoveryFailure(
        failure: VaultStorageRecovery.Failure,
        reason: VaultStoreFailureView.Reason,
    ) {
        #expect(VaultRoot.failureReason(forRecoveryError: failure) == reason)
    }

    /// Anything else recovery throws, such as the file system failing, leaves the store unreadable.
    @Test
    func failureReason_forAnyOtherError_isStoreUnreadable() {
        #expect(VaultRoot.failureReason(forRecoveryError: CocoaError(.fileReadUnknown)) == .storeUnreadable)
    }
}
