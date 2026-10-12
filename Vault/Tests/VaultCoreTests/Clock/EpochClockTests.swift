import Foundation
import Testing
import VaultCore

enum EpochClockTests {
    struct MockTests {
        @Test(arguments: [
            1,
            1234,
            Date.now.timeIntervalSince1970,
        ])
        func isInjectedTime(injectedTime: Double) {
            let sut = EpochClockMock(currentTime: injectedTime)

            #expect(sut.currentTime == injectedTime)
        }
    }

    struct ImplTests {
        @Test
        func isCurrentTime() {
            let currentTime = Date.now.timeIntervalSince1970
            let sut = EpochClockImpl()

            let difference = abs(currentTime - sut.currentTime)
            #expect(difference < 0.5, "This should be the time as of now")
        }

        @Test
        func runsOffsetAheadOfTheCurrentTime() {
            let currentTime = Date.now.timeIntervalSince1970
            let sut = EpochClockImpl(offset: 20)

            #expect(abs(currentTime + 20 - sut.currentTime) < 0.5)
            #expect(abs(sut.currentDate.timeIntervalSince1970 - sut.currentTime) < 0.5)
        }
    }
}
