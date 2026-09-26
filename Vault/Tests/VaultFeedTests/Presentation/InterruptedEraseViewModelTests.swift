import Foundation
import FoundationExtensions
import TestHelpers
import Testing
@testable import VaultFeed

/// The launch path for an erase the app was stopped in the middle of: the vault is shown only once it's finished.
@MainActor
struct InterruptedEraseViewModelTests {
    @Test
    func init_isErasingAndErasesNothingYet() {
        let erases = SharedMutex(0)

        let sut = InterruptedEraseViewModel(erase: { erases.modify { $0 += 1 } })

        #expect(sut.state == .erasing)
        #expect(erases.value == 0)
    }

    @Test
    func finish_whenTheEraseSucceeds_isErased() async {
        let erases = SharedMutex(0)
        let sut = InterruptedEraseViewModel(erase: { erases.modify { $0 += 1 } })

        await sut.finish()

        #expect(sut.state == .erased)
        #expect(erases.value == 1)
    }

    /// A failed erase isn't swallowed: the vault stays hidden, and trying again can finish it.
    @Test
    func finish_whenTheEraseFails_failsThenTryingAgainFinishes() async {
        let failuresLeft = SharedMutex(1)
        let sut = InterruptedEraseViewModel(erase: {
            let fails = failuresLeft.modify { failures in
                defer { failures -= 1 }
                return failures > 0
            }
            if fails {
                throw TestError()
            }
        })

        await sut.finish()
        #expect(sut.state == .failed)

        await sut.finish()
        #expect(sut.state == .erased)
    }

    /// Finishing again once it's done, from a second `setup()` say, would erase the fresh store.
    @Test
    func finish_onceErased_doesNotEraseAgain() async {
        let erases = SharedMutex(0)
        let sut = InterruptedEraseViewModel(erase: { erases.modify { $0 += 1 } })

        await sut.finish()
        await sut.finish()

        #expect(erases.value == 1)
        #expect(sut.state == .erased)
    }

    @Test
    func finish_whileAlreadyFinishing_doesNotStartAnother() async {
        let erases = SharedMutex(0)
        let sut = InterruptedEraseViewModel(erase: {
            erases.modify { $0 += 1 }
            try await Task.sleep(for: .milliseconds(50))
        })

        async let first: Void = sut.finish()
        async let second: Void = sut.finish()
        _ = await (first, second)

        #expect(erases.value == 1)
        #expect(sut.state == .erased)
    }
}
