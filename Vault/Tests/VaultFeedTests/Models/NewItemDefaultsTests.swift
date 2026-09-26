import Foundation
import Testing
import VaultFeed

struct NewItemDefaultsTests {
    @Test
    func init_startsWithEverythingOff() {
        let sut = NewItemDefaults()

        #expect(sut.lockNewItems == false)
        #expect(sut.showNewCodesInQuickType == false)
        #expect(sut.lockState == .notLocked)
    }

    @Test
    func lockState_isLockedWhenLockingNewItems() {
        let sut = NewItemDefaults(lockNewItems: true)

        #expect(sut.lockState == .lockedWithNativeSecurity)
    }
}
