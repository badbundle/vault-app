import Foundation
import TestHelpers
import Testing
@testable import VaultFeed

@MainActor
struct TOTPPreviewViewRepositoryImplTests {
    @Test
    func init_hasNoSideEffects() {
        let sut = makeSUT()

        #expect(sut.cachedViewsCount == 0)
        #expect(sut.cachedPeriodStateCount == 0)
        #expect(sut.cachedTimerControllerCount == 0)
    }

    @Test
    func previewViewModel_returnsSameViewModelInstanceUsingCachedViewModels() {
        let sut = makeSUT()

        let sharedID = Identifier<VaultItem>.new()
        let viewModel1 = sut.previewViewModel(metadata: anyVaultItemMetadata(id: sharedID), code: anyTOTPCode())
        #expect(sut.cachedViewsCount == 1)
        let viewModel2 = sut.previewViewModel(metadata: anyVaultItemMetadata(id: sharedID), code: anyTOTPCode())
        #expect(sut.cachedViewsCount == 1)
        let viewModel3 = sut.previewViewModel(metadata: anyVaultItemMetadata(id: .new()), code: anyTOTPCode())
        #expect(sut.cachedViewsCount == 2)

        #expect(viewModel1 === viewModel2)
        #expect(viewModel1 !== viewModel3, "View model 3 has a different ID")
        #expect(viewModel2 !== viewModel3, "View model 3 has a different ID")
    }

    @Test
    func timerUpdater_returnsSameInstanceUsingCachedViewModels() {
        let factory = OTPCodeTimerUpdaterFactoryMock()
        factory.makeUpdaterHandler = { _ in OTPCodeTimerUpdaterMock() }
        let sut = makeSUT(factory: factory)

        let sharedPeriod = 123 as UInt64
        let updater1 = sut.timerUpdater(period: sharedPeriod)
        #expect(sut.cachedTimerControllerCount == 1)
        let updater2 = sut.timerUpdater(period: sharedPeriod)
        #expect(sut.cachedTimerControllerCount == 1)
        let updater3 = sut.timerUpdater(period: 99)
        #expect(sut.cachedTimerControllerCount == 2)

        #expect(updater1 === updater2)
        #expect(updater1 !== updater3, "Updater 3 is different")
        #expect(updater2 !== updater3, "Updater 3 is different")
    }

    @Test
    func timerPeriodState_returnsSameInstanceUsingCachedViewModels() {
        let sut = makeSUT()

        let sharedPeriod = 123 as UInt64
        let state1 = sut.timerPeriodState(period: sharedPeriod)
        #expect(sut.cachedPeriodStateCount == 1)
        let state2 = sut.timerPeriodState(period: sharedPeriod)
        #expect(sut.cachedPeriodStateCount == 1)
        let state3 = sut.timerPeriodState(period: 99)
        #expect(sut.cachedPeriodStateCount == 2)

        #expect(state1 === state2)
        #expect(state1 !== state3, "State 3 is different")
        #expect(state2 !== state3, "State 3 is different")
    }

    @Test
    func textToCopyForVaultItem_isNilIfCacheEmpty() {
        let sut = makeSUT()

        let copyAction = sut.textToCopyForVaultItem(id: .new())

        #expect(copyAction == nil)
    }

    @Test
    func textToCopyForVaultItem_isNilWhenCodeIsObfuscated() {
        let sut = makeSUT()

        let id = Identifier<VaultItem>()
        _ = sut.previewViewModel(metadata: anyVaultItemMetadata(id: id), code: anyTOTPCode())
        let code = sut.textToCopyForVaultItem(id: id)

        #expect(code == nil, "Code is initially obfuscated, so this should be nil")
    }

    @Test
    func textToCopyForVaultItem_isCopyTextIfCodeHasBeenGenerated() {
        let sut = makeSUT()
        let id = Identifier<VaultItem>()
        let viewModel = sut.previewViewModel(metadata: anyVaultItemMetadata(id: id), code: anyTOTPCode())
        viewModel.update(.visible("123456"))

        let code = sut.textToCopyForVaultItem(id: id)

        #expect(code == .init(text: "123456", requiresAuthenticationToCopy: false, contentType: .otp))
    }

    @Test
    func textToCopyForVaultItem_requiresAuthenticationToCopyIfLocked() {
        let sut = makeSUT()
        let id = Identifier<VaultItem>()
        let viewModel = sut.previewViewModel(metadata: anyVaultItemMetadata(id: id), code: anyTOTPCode())
        viewModel.update(.locked(code: "123456"))

        let code = sut.textToCopyForVaultItem(id: id)

        #expect(code == .init(text: "123456", requiresAuthenticationToCopy: true, contentType: .otp))
    }

    @Test
    func stopAllTimers_cancelsAllTimers() async {
        let updater = OTPCodeTimerUpdaterMock()
        let sut = makeSUT(updater: updater)
        _ = sut.timerUpdater(period: 100)

        await confirmation { confirmation in
            updater.cancelHandler = {
                confirmation.confirm()
            }
            sut.stopAllTimers()
        }
    }

    @Test
    func restartAllTimers_restartsAllTimers() async {
        let updater = OTPCodeTimerUpdaterMock()
        let sut = makeSUT(updater: updater)
        _ = sut.timerUpdater(period: 100)

        await confirmation { confirmation in
            updater.recalculateHandler = {
                confirmation.confirm()
            }
            sut.restartAllTimers()
        }
    }

    @Test
    func obfuscateForPrivacy_obfuscatesViewModelsForPrivacy() {
        let sut = makeSUT()
        let viewModel = sut.previewViewModel(metadata: anyVaultItemMetadata(), code: anyTOTPCode())
        viewModel.update(.visible("123456"))

        sut.obfuscateForPrivacy()

        #expect(viewModel.code == .obfuscated(.privacy))
    }

    @Test
    func unobfuscateForPrivacy_unobfuscatesCodesHiddenForPrivacy() {
        let sut = makeSUT()
        let viewModel = sut.previewViewModel(metadata: anyVaultItemMetadata(), code: anyTOTPCode())
        viewModel.update(.visible("123456"))
        viewModel.update(.obfuscated(.privacy))

        sut.unobfuscateForPrivacy()

        #expect(viewModel.code == .visible("123456"))
    }

    @Test
    func vaultItemCacheClear_removesItemsMatchingIDFromCache() async {
        let sut = makeSUT()

        let id1 = Identifier<VaultItem>()
        let id2 = Identifier<VaultItem>()

        _ = sut.previewViewModel(metadata: anyVaultItemMetadata(id: id1), code: anyTOTPCode(period: 100))
        _ = sut.previewViewModel(metadata: anyVaultItemMetadata(id: id2), code: anyTOTPCode(period: 100))
        _ = sut.timerPeriodState(period: 100)
        _ = sut.timerPeriodState(period: 101)
        _ = sut.timerUpdater(period: 100)
        _ = sut.timerUpdater(period: 101)

        #expect(sut.cachedViewsCount == 2)
        #expect(sut.cachedPeriodStateCount == 2)
        #expect(sut.cachedTimerControllerCount == 2)

        await sut.vaultItemCacheClear(forVaultItemWithID: id1)

        #expect(sut.cachedViewsCount == 1)
        #expect(sut.cachedPeriodStateCount == 2, "Period-based state is not invalidated")
        #expect(sut.cachedTimerControllerCount == 2, "Period-based state is not invalidated")
    }

    @Test
    func vaultItemCacheClearAll_removesItemsAllItemsFromCache() async {
        let sut = makeSUT()

        _ = sut.previewViewModel(metadata: anyVaultItemMetadata(id: .new()), code: anyTOTPCode(period: 100))
        _ = sut.previewViewModel(metadata: anyVaultItemMetadata(id: .new()), code: anyTOTPCode(period: 100))
        _ = sut.timerPeriodState(period: 100)
        _ = sut.timerPeriodState(period: 101)
        _ = sut.timerUpdater(period: 100)
        _ = sut.timerUpdater(period: 101)

        #expect(sut.cachedViewsCount == 2)
        #expect(sut.cachedPeriodStateCount == 2)
        #expect(sut.cachedTimerControllerCount == 2)

        await sut.vaultItemCacheClearAll()

        #expect(sut.cachedViewsCount == 0)
        #expect(sut.cachedPeriodStateCount == 0)
        #expect(sut.cachedTimerControllerCount == 0)
    }
}

// MARK: - Helpers

extension TOTPPreviewViewRepositoryImplTests {
    private func makeSUT(
        clock: EpochClockMock = EpochClockMock(currentTime: 100),
        timer: IntervalTimerMock = IntervalTimerMock(),
        updater: OTPCodeTimerUpdaterMock = OTPCodeTimerUpdaterMock(),
    ) -> TOTPPreviewViewRepositoryImpl {
        let factory = OTPCodeTimerUpdaterFactoryMock()
        factory.makeUpdaterHandler = { _ in updater }
        return TOTPPreviewViewRepositoryImpl(clock: clock, timer: timer, updaterFactory: factory)
    }

    private func makeSUT(
        clock: EpochClockMock = EpochClockMock(currentTime: 100),
        timer: IntervalTimerMock = IntervalTimerMock(),
        factory: OTPCodeTimerUpdaterFactoryMock,
    ) -> TOTPPreviewViewRepositoryImpl {
        TOTPPreviewViewRepositoryImpl(clock: clock, timer: timer, updaterFactory: factory)
    }
}
