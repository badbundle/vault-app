import Foundation
import FoundationExtensions
import VaultCore

/// @mockable
@MainActor
public protocol TOTPPreviewViewRepository: VaultItemCache, VaultItemCopyActionHandler {
    func previewViewModel(metadata: VaultItem.Metadata, code: TOTPAuthCode) -> OTPCodePreviewViewModel
    func timerPeriodState(period: UInt64) -> OTPCodeTimerPeriodState
    func timerUpdater(period: UInt64) -> any OTPCodeTimerUpdater
    func restartAllTimers()
    func stopAllTimers()
    func obfuscateForPrivacy()
    func unobfuscateForPrivacy()
}

public final class TOTPPreviewViewRepositoryImpl: TOTPPreviewViewRepository {
    private let clock: any EpochClock
    private let timer: any IntervalTimer
    private let updaterFactory: any OTPCodeTimerUpdaterFactory
    private var timerUpdaterCache = Cache<UInt64, any OTPCodeTimerUpdater>()
    private var timerPeriodStateCache = Cache<UInt64, OTPCodeTimerPeriodState>()
    private var nextCodeWindowCache = Cache<UInt64, TOTPNextCodeWindow>()
    private var viewModelCache = Cache<Identifier<VaultItem>, OTPCodePreviewViewModel>()

    public init(
        clock: any EpochClock,
        timer: any IntervalTimer,
        updaterFactory: any OTPCodeTimerUpdaterFactory,
    ) {
        self.clock = clock
        self.timer = timer
        self.updaterFactory = updaterFactory
    }

    public func previewViewModel(metadata: VaultItem.Metadata, code: TOTPAuthCode) -> OTPCodePreviewViewModel {
        viewModelCache.getOrCreateValue(for: metadata.id) {
            let totpGenerator = TOTPGenerator(generator: code.data.hotpGenerator(), timeInterval: code.period)
            let codePublisher = TOTPCodePublisher(
                timer: timerUpdater(period: code.period),
                totpGenerator: totpGenerator,
            )
            return OTPCodePreviewViewModel(
                accountName: code.data.accountName,
                issuer: code.data.issuer,
                color: metadata.color ?? .default,
                isLocked: metadata.lockState.isLocked,
                codePublisher: codePublisher,
                nextCodePublisher: TOTPNextCodePublisher(
                    window: nextCodeWindow(period: code.period),
                    totpGenerator: totpGenerator,
                ),
            )
        }
    }

    private func nextCodeWindow(period: UInt64) -> TOTPNextCodeWindow {
        nextCodeWindowCache.getOrCreateValue(for: period) {
            TOTPNextCodeWindow(timerUpdater: timerUpdater(period: period), intervalTimer: timer, clock: clock)
        }
    }

    public func timerUpdater(period: UInt64) -> any OTPCodeTimerUpdater {
        timerUpdaterCache.getOrCreateValue(for: period) {
            updaterFactory.makeUpdater(period: period)
        }
    }

    public func timerPeriodState(period: UInt64) -> OTPCodeTimerPeriodState {
        timerPeriodStateCache.getOrCreateValue(for: period) {
            let timerController = timerUpdater(period: period)
            return OTPCodeTimerPeriodState(statePublisher: timerController.timerUpdatedPublisher)
        }
    }

    public func restartAllTimers() {
        for timerUpdater in timerUpdaterCache.values {
            timerUpdater.recalculate()
        }
    }

    /// Stops the next code windows too. They follow the timers, so they pick up again when those restart.
    public func stopAllTimers() {
        for timerUpdater in timerUpdaterCache.values {
            timerUpdater.cancel()
        }
        for nextCodeWindow in nextCodeWindowCache.values {
            nextCodeWindow.cancel()
        }
    }

    public func obfuscateForPrivacy() {
        for viewModel in viewModelCache.values {
            viewModel.update(.obfuscated(.privacy))
        }
    }

    public func unobfuscateForPrivacy() {
        for viewModel in viewModelCache.values {
            viewModel.updateRemovePrivacyObfuscation()
        }
    }
}

extension TOTPPreviewViewRepositoryImpl: VaultItemCopyActionHandler {
    public func textToCopyForVaultItem(id: Identifier<VaultItem>) -> VaultTextCopyAction? {
        viewModelCache[id]?.pasteboardCopyText
    }
}

// MARK: - Caching

extension TOTPPreviewViewRepositoryImpl: VaultItemCache {
    public nonisolated func vaultItemCacheClearAll() async {
        // remove EVERYTHING from cache
        await MainActor.run {
            viewModelCache.removeAll()
            timerPeriodStateCache.removeAll()
            nextCodeWindowCache.removeAll()
            timerUpdaterCache.removeAll()
        }
    }

    public nonisolated func vaultItemCacheClear(forVaultItemWithID id: Identifier<VaultItem>) async {
        // don't invalidate period caches, as they are independant of the code detail
        await MainActor.run {
            viewModelCache.remove(key: id)
        }
    }

    var cachedViewsCount: Int {
        viewModelCache.count
    }

    var cachedTimerControllerCount: Int {
        timerUpdaterCache.count
    }

    var cachedPeriodStateCount: Int {
        timerPeriodStateCache.count
    }

    var cachedNextCodeWindowCount: Int {
        nextCodeWindowCache.count
    }
}
