import Combine
import Foundation
import FoundationExtensions
import SwiftUI
import TestHelpers
import Testing
import VaultCore
import VaultFeed
@testable import VaultiOS

@MainActor
final class TOTPPreviewViewGeneratorTests {
    @Test
    func init_hasNoSideEffects() {
        let factory = makeTOTPPreviewViewFactoryMock()
        let repository = TOTPPreviewViewRepositoryMock()
        _ = makeSUT(factory: factory, repository: repository)

        #expect(factory.makeTOTPViewCallCount == 0)
        #expect(repository.previewViewModelCallCount == 0)
        #expect(repository.timerUpdaterCallCount == 0)
        #expect(repository.timerPeriodStateCallCount == 0)
        #expect(repository.stopAllTimersCallCount == 0)
        #expect(repository.restartAllTimersCallCount == 0)
        #expect(repository.textToCopyForVaultItemCallCount == 0)
        #expect(repository.vaultItemCacheClearCallCount == 0)
    }

    @Test
    func makeOTPView_generatesViews() {
        let repository = TOTPPreviewViewRepositoryMock()
        repository.previewViewModelHandler = { _, _ in
            MainActor.assumeIsolated {
                OTPCodePreviewViewModel(
                    accountName: "",
                    issuer: "",
                    color: .black,
                    isLocked: false,
                    fixedCodeState: .visible("12345"),
                )
            }
        }
        repository.timerPeriodStateHandler = { _ in
            MainActor.assumeIsolated {
                OTPCodeTimerPeriodState(
                    statePublisher: Just(OTPCodeTimerState(currentTime: 100, period: 10))
                        .setFailureType(to: Never.self).eraseToAnyPublisher(),
                )
            }
        }
        repository.timerUpdaterHandler = { _ in
            MainActor.assumeIsolated {
                OTPCodeTimerUpdaterMock()
            }
        }
        let factory = TOTPPreviewViewFactoryMock()
        factory.makeTOTPViewHandler = { _, _, _, _ in AnyView(Color.green) }
        let sut = makeSUT(factory: factory, repository: repository)

        let view = sut.makeVaultPreviewView(item: anyTOTPCode(), metadata: uniqueMetadata(), behaviour: .normal)

        assertSnapshot(of: view.frame(width: 100, height: 100), as: .image)
    }

    @Test
    func scenePhaseDidChange_activeUnobfuscatesAndRestartsAllTimers() {
        let factory = makeTOTPPreviewViewFactoryMock()
        let repository = TOTPPreviewViewRepositoryMock()
        let sut = makeSUT(factory: factory, repository: repository)

        sut.scenePhaseDidChange(to: .active)

        #expect(repository.restartAllTimersCallCount == 1)
        #expect(repository.unobfuscateForPrivacyCallCount == 1)
        #expect(repository.obfuscateForPrivacyCallCount == 0)
        #expect(repository.stopAllTimersCallCount == 0)
    }

    @Test(arguments: [ScenePhase.background, .inactive])
    func scenePhaseDidChange_cancelsAllTimers(phase: ScenePhase) {
        let factory = makeTOTPPreviewViewFactoryMock()
        let repository = TOTPPreviewViewRepositoryMock()
        let sut = makeSUT(factory: factory, repository: repository)

        sut.scenePhaseDidChange(to: phase)

        #expect(repository.restartAllTimersCallCount == 0)
        #expect(repository.obfuscateForPrivacyCallCount == 1)
        #expect(repository.unobfuscateForPrivacyCallCount == 0)
        #expect(repository.stopAllTimersCallCount == 1)
    }

    @Test
    func clearViewCache_clearsRepositoryCache() async {
        let repository = TOTPPreviewViewRepositoryMock()
        let sut = makeSUT(repository: repository)

        await sut.clearViewCache()

        #expect(repository.vaultItemCacheClearAllCallCount == 1)
    }

    @Test
    func didAppear_restartsAllTimers() {
        let factory = makeTOTPPreviewViewFactoryMock()
        let repository = TOTPPreviewViewRepositoryMock()
        let sut = makeSUT(factory: factory, repository: repository)

        sut.didAppear()

        #expect(repository.restartAllTimersCallCount == 1)
        #expect(repository.obfuscateForPrivacyCallCount == 0)
        #expect(repository.stopAllTimersCallCount == 0)
    }
}

extension TOTPPreviewViewGeneratorTests {
    private typealias SUT = TOTPPreviewViewGenerator<TOTPPreviewViewFactoryMock>

    private func makeSUT(
        factory: TOTPPreviewViewFactoryMock = makeTOTPPreviewViewFactoryMock(),
        repository: TOTPPreviewViewRepositoryMock = TOTPPreviewViewRepositoryMock(),
    ) -> SUT {
        SUT(viewFactory: factory, repository: repository)
    }

    private func anyTOTPCode() -> TOTPAuthCode {
        let codeData = OTPAuthCodeData(secret: .empty(), accountName: "Test")
        return .init(data: codeData)
    }
}

extension OTPCodeTimerUpdaterFactoryMock {
    static func defaultMock() -> OTPCodeTimerUpdaterFactoryMock {
        let s = OTPCodeTimerUpdaterFactoryMock()
        s.makeUpdaterHandler = { _ in
            MainActor.assumeIsolated {
                OTPCodeTimerUpdaterMock()
            }
        }
        return s
    }
}

@MainActor
private func makeTOTPPreviewViewFactoryMock() -> TOTPPreviewViewFactoryMock {
    let mock = TOTPPreviewViewFactoryMock()
    mock.makeTOTPViewHandler = { _, _, _, _ in AnyView(Text("Nice")) }
    return mock
}
