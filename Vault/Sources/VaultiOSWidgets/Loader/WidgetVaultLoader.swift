import Foundation
import FoundationExtensions
import VaultCore
public import VaultFeed

/// Reads the shared vault store from the widget extension process and
/// surfaces only those items that pass `VaultItemWidgetEligibility`.
///
/// The widget extension cannot link `VaultiOS` (and therefore cannot use
/// `VaultRoot.vaultStore`), so this type opens its own `PersistedLocalVaultStore`
/// pointed at the same App Group container.
public actor WidgetVaultLoader {
    /// The capabilities the widget process needs: reads, plus advancing an
    /// HOTP counter. Deliberately narrower than `VaultStore` — the extension
    /// can never insert, update, delete, reorder, or export.
    public typealias WidgetStore = VaultStoreHOTPIncrementer & VaultStoreReader

    public typealias StoreFactory = @Sendable () throws -> any WidgetStore

    /// Process-wide default instance. Widget timeline providers should reuse
    /// the same loader across calls so the underlying `ModelContainer` is
    /// built once.
    public static let shared = WidgetVaultLoader()

    private let makeStore: StoreFactory
    private var store: (any WidgetStore)?
    private let appLockSettings: AppLockSettingsStore
    /// Whether the vault is in the plain store, with no change of mode underway.
    private let isVaultPlain: @Sendable () -> Bool

    public init(store: (any WidgetStore)? = nil, appLockSettings: AppLockSettingsStore = .shared()) {
        if let store {
            self.store = store
            makeStore = { store }
            isVaultPlain = { true }
        } else {
            self.store = nil
            makeStore = Self.makeSharedStore
            isVaultPlain = { VaultStorageState.isPlain(inDirectory: VaultSharedStorage.directory()) }
        }
        self.appLockSettings = appLockSettings
    }

    /// - Parameter isVaultPlain: Whether the vault is in the plain store, with no change of mode underway. The store
    ///   is only opened and read while it is.
    public init(
        appLockSettings: AppLockSettingsStore = .shared(),
        isVaultPlain: @escaping @Sendable () -> Bool,
        makeStore: @escaping StoreFactory,
    ) {
        self.makeStore = makeStore
        store = nil
        self.appLockSettings = appLockSettings
        self.isVaultPlain = isVaultPlain
    }

    /// Whether the widget shows the vault as locked: while the app lock is on, and while the vault is encrypted with
    /// the App Lock Password, or being converted. The loader hands out no items then either, so the widget's actions
    /// can't copy or advance a code, and its configuration can't list the vault's items.
    public nonisolated var isLocked: Bool {
        appLockSettings.isEnabled || !isVaultPlain()
    }

    /// All items that are currently eligible to appear in a widget. Hidden,
    /// locked, killphrase-protected, and search-passphrase items are filtered
    /// out — see `VaultItemWidgetEligibility`.
    public func eligibleItems() async throws -> [VaultItem] {
        let result = try await retrieveItems()
        return result.items.filter(VaultItemWidgetEligibility.isEligible)
    }

    /// Fetch a single eligible item by id. Returns `nil` when the item does
    /// not exist or has become ineligible since the user configured the widget.
    /// The two states are indistinguishable to callers by design (manifesto C2).
    public func eligibleItem(id: UUID) async throws -> VaultItem? {
        let result = try await retrieveItems()
        guard let item = result.items.first(where: { $0.id.rawValue == id }) else {
            return nil
        }
        return VaultItemWidgetEligibility.isEligible(item) ? item : nil
    }

    /// Renders the current TOTP value for an eligible item.
    public func currentTOTPCode(id: UUID, date: Date = Date()) async throws -> String? {
        guard let item = try await eligibleItem(id: id),
              case let .otpCode(otp) = item.item,
              case let .totp(period) = otp.type
        else {
            return nil
        }

        let code = TOTPAuthCode(period: period, data: otp.data)
        return try code.renderCode(epochSeconds: UInt64(date.timeIntervalSince1970))
    }

    /// Advances an eligible HOTP item and returns the freshly generated code.
    ///
    /// This is the only write the widget process performs. The store is still
    /// opened `.openOnly` so a transient open failure can never trigger the
    /// recovery path from an extension (see #526).
    public func incrementAndRenderHOTPCode(id: UUID) async throws -> String? {
        guard let item = try await eligibleItem(id: id),
              case let .otpCode(otp) = item.item,
              case let .hotp(counter) = otp.type
        else {
            return nil
        }

        let currentStore = try store ?? openStore()
        let nextCounter = counter + 1
        let code = try HOTPAuthCode(counter: nextCounter, data: otp.data).renderCode()
        try await currentStore.incrementCounter(id: item.id)
        return code
    }

    /// The plain store, guarded, so a HOTP increment can't land in it after the app has started converting it to an
    /// encrypted vault.
    private static func makeSharedStore() throws -> any WidgetStore {
        let directory = VaultSharedStorage.directory()
        let store = try PersistedLocalVaultStoreFactory(storageDirectory: directory, recoveryMode: .openOnly)
            .makeVaultStoreOrThrow()
        return GuardedPlainVaultStore(store: store, directory: directory)
    }

    /// Every read goes through here, so none reaches the vault while it's locked: nothing opens the plain store once
    /// the vault is encrypted, or while it's being converted.
    private func retrieveItems() async throws -> VaultRetrievalResult<VaultItem> {
        guard !isLocked else { return .empty() }
        let currentStore = try store ?? openStore()
        do {
            return try await currentStore.retrieve(query: .init())
        } catch {
            store = nil
            throw error
        }
    }

    private func openStore() throws -> any WidgetStore {
        let openedStore = try makeStore()
        store = openedStore
        return openedStore
    }
}
