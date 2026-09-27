import Foundation
import FoundationExtensions
import TestHelpers
import Testing
@testable import VaultFeed

/// The failure screen's way out when the vault's data is missing: an erase that only ever runs when asked.
@MainActor
struct MissingVaultViewModelTests {
    @Test
    func init_isWaitingAndErasesNothing() {
        let erases = SharedMutex(0)

        let sut = MissingVaultViewModel(erase: { erases.modify { $0 += 1 } })

        #expect(sut.state == .waiting)
        #expect(erases.value == 0)
    }

    @Test
    func eraseAndStartAgain_whenTheEraseSucceeds_isErased() async {
        let erases = SharedMutex(0)
        let sut = MissingVaultViewModel(erase: { erases.modify { $0 += 1 } })

        await sut.eraseAndStartAgain()

        #expect(sut.state == .erased)
        #expect(erases.value == 1)
    }

    @Test
    func eraseAndStartAgain_whenTheEraseFails_failsThenTryingAgainFinishes() async {
        let failuresLeft = SharedMutex(1)
        let sut = MissingVaultViewModel(erase: {
            let fails = failuresLeft.modify { failures in
                defer { failures -= 1 }
                return failures > 0
            }
            if fails {
                throw TestError()
            }
        })

        await sut.eraseAndStartAgain()
        #expect(sut.state == .failed)

        await sut.eraseAndStartAgain()
        #expect(sut.state == .erased)
    }

    /// Once the vault is erased, the fresh store is the vault: asking again mustn't erase it.
    @Test
    func eraseAndStartAgain_onceErased_erasesNothingMore() async {
        let erases = SharedMutex(0)
        let sut = MissingVaultViewModel(erase: { erases.modify { $0 += 1 } })
        await sut.eraseAndStartAgain()

        await sut.eraseAndStartAgain()

        #expect(erases.value == 1)
        #expect(sut.state == .erased)
    }
}
