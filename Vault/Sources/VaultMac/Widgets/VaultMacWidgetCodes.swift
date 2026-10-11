import Foundation
import VaultFeed

/// Hands the Mac's widgets the codes they may show while the vault is unlocked, and takes them back the moment it
/// locks (docs/mac-app.md, "Widgets", G98).
///
/// The Mac's App Lock Password is always on, so a widget that read the vault itself would only ever show it locked
/// (G44). Instead, while the vault is unlocked, the app works out each code a widget may show for the next few
/// minutes (`WidgetCodeHandoff`), and keeps them where only it and its widget extension can read them
/// (`WidgetCodeHandoffStore`). It never hands over a secret: the widget extension can't open the vault, or work a code
/// out, and has nothing once the codes run out.
///
/// - **Handing over** happens when the vault unlocks, whenever its items change, and every half window while it stays
///   unlocked, so the codes never run out while it is. Only an unlocked encrypted vault's codes are handed over:
///   before the App Lock Password is first set there's no vault.
/// - **Taking back** happens at once whenever the vault locks, whatever locked it (`AppLockService`'s purge), when
///   Vault quits, and at launch, in case it last stopped without locking. If the codes can be neither deleted nor
///   replaced, as can happen while the Mac is locked, it tries again every few seconds, until they would have run out
///   anyway.
///
/// Each time, it asks WidgetKit to reload the widgets. If macOS holds a reload back, a widget goes on showing the codes
/// it had until they run out (`WidgetCodeHandoff.window`), and then shows Vault locked.
///
/// The codes are worked out off the main actor. They're handed over on it, as the vault locks on it, and only if it
/// hasn't locked since they were worked out, so codes are never handed over after a lock.
@MainActor
final class VaultMacWidgetCodes {
    /// How often codes are handed over again while the vault stays unlocked: halfway through a handoff's window.
    nonisolated static let refreshInterval: Duration = .seconds(WidgetCodeHandoff.window / 2)
    /// How often taking the codes back is tried again, if it fails.
    nonisolated static let withdrawalRetryInterval: Duration = .seconds(10)
    /// How many times it's tried again: until the codes would have run out anyway.
    nonisolated static let withdrawalRetries = Int(WidgetCodeHandoff.window / 10)

    private let store: WidgetCodeHandoffStore
    private let isUnlocked: @MainActor () -> Bool
    private let retrieveItems: @Sendable () async throws -> [VaultItem]?
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void
    private let reloadWidgets: @MainActor () -> Void

    /// Counts the times the codes were taken back. Codes worked out before the latest are never handed over.
    private var withdrawals = 0
    /// Counts the times the codes were worked out, so only the latest are handed over.
    private var updates = 0
    /// Whether the widgets were given codes since they were last taken back, so they need reloading.
    private var isHandedOver = false
    /// Working the codes out, kept so tests can wait for it.
    private(set) var pendingUpdate: Task<Void, Never>?
    /// Waiting to hand codes over again.
    private(set) var pendingRefresh: Task<Void, Never>?
    /// Trying again to take the codes back, after it failed.
    private(set) var pendingWithdrawal: Task<Void, Never>?

    /// - Parameters:
    ///   - isUnlocked: Whether the app is unlocked.
    ///   - retrieveItems: The open vault's items, or `nil` if no encrypted vault is open.
    ///   - reloadWidgets: Asks WidgetKit to reload every widget.
    init(
        store: WidgetCodeHandoffStore,
        isUnlocked: @escaping @MainActor () -> Bool,
        retrieveItems: @escaping @Sendable () async throws -> [VaultItem]?,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        reloadWidgets: @escaping @MainActor () -> Void,
    ) {
        self.store = store
        self.isUnlocked = isUnlocked
        self.retrieveItems = retrieveItems
        self.now = now
        self.sleep = sleep
        self.reloadWidgets = reloadWidgets
    }

    /// Hands the widgets the open vault's codes, if the app is unlocked, or takes them back if it isn't.
    func update() {
        guard isUnlocked() else {
            withdraw()
            return
        }
        updates += 1
        let update = updates
        let withdrawals = withdrawals
        pendingUpdate = Task { [retrieveItems, now] in
            let handoff = await Self.makeHandoff(items: try? retrieveItems(), now: now())
            handOver(handoff, update: update, withdrawals: withdrawals)
        }
    }

    /// Takes the codes back from the widgets, at once.
    func withdraw() {
        withdrawals += 1
        pendingUpdate?.cancel()
        pendingUpdate = nil
        pendingRefresh?.cancel()
        pendingRefresh = nil
        pendingWithdrawal?.cancel()
        pendingWithdrawal = nil
        do {
            try store.withdraw()
        } catch {
            retryWithdrawal()
        }
        if isHandedOver {
            isHandedOver = false
            reloadWidgets()
        }
    }

    /// Takes back whatever an earlier run of the app left, which stopped without locking if there's any: at launch.
    func withdrawLeftovers() {
        isHandedOver = true
        withdraw()
    }

    /// Tries again to take the codes back, every few seconds, until it can, the codes would have run out anyway, or
    /// the app hands new ones over.
    private func retryWithdrawal() {
        pendingWithdrawal = Task { [store, sleep] in
            for _ in 0 ..< Self.withdrawalRetries {
                do {
                    try await sleep(Self.withdrawalRetryInterval)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                if (try? store.withdraw()) != nil {
                    return
                }
            }
        }
    }

    private func handOver(_ handoff: WidgetCodeHandoff?, update: Int, withdrawals: Int) {
        guard update == updates, withdrawals == self.withdrawals, isUnlocked() else { return }
        guard let handoff else {
            withdraw()
            return
        }
        // New codes replace any that couldn't be taken back.
        pendingWithdrawal?.cancel()
        pendingWithdrawal = nil
        do {
            try store.publish(handoff)
        } catch {
            withdraw()
            return
        }
        isHandedOver = true
        reloadWidgets()
        pendingRefresh = Task { [sleep] in
            do {
                try await sleep(Self.refreshInterval)
            } catch {
                return
            }
            self.update()
        }
    }

    /// Works the codes out, off the main actor.
    private nonisolated static func makeHandoff(items: [VaultItem]?, now: Date) async -> WidgetCodeHandoff? {
        items.map { WidgetCodeHandoff(items: $0, now: now) }
    }
}
