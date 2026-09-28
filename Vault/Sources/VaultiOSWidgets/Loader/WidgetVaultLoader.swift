import Foundation
import FoundationExtensions
import VaultCore
public import VaultFeed

/// Reads the shared vault from the widget extension process and surfaces only those items that pass
/// `VaultItemWidgetEligibility`.
///
/// The widget extension cannot link `VaultiOS` (and therefore cannot use `VaultRoot.vaultStore`), so this type opens
/// the vault itself, as the App Group container holds it now (`VaultAccessMode`): the plain store, or the encrypted
/// file with the device key while the App Lock Password is off. While only the password opens it, the widget shows
/// it locked.
///
/// With the device key, the vault is opened only to show it (`VaultStoreSession.openedToShowWithDeviceKey`): a widget
/// hasn't the memory to save the whole file, so it sends a HOTP increment to the app instead
/// (`advancesHOTPInTheApp`).
public actor WidgetVaultLoader {
    /// The capabilities the widget process needs: reads, plus advancing an
    /// HOTP counter. Deliberately narrower than `VaultStore` — the extension
    /// can never insert, update, delete, reorder, or export.
    public typealias WidgetStore = VaultStoreHOTPIncrementer & VaultStoreReader

    /// Opens the vault as it can be opened now: plain, or with the device key.
    public typealias StoreFactory = @Sendable (VaultAccessMode) async throws -> any WidgetStore

    /// Process-wide default instance. Widget timeline providers should reuse
    /// the same loader across calls so the underlying `ModelContainer` is
    /// built once.
    public static let shared = WidgetVaultLoader()

    private let makeStore: StoreFactory
    /// The plain store, once opened. It reads the vault from disk every time, so it's kept.
    private var plainStore: (any WidgetStore)?
    private let appLockSettings: AppLockSettingsStore
    /// How the vault can be opened now.
    private let accessMode: @Sendable () -> VaultAccessMode

    public init(store: (any WidgetStore)? = nil, appLockSettings: AppLockSettingsStore = .shared()) {
        if let store {
            plainStore = store
            makeStore = { _ in store }
            accessMode = { .plain }
        } else {
            plainStore = nil
            makeStore = Self.makeSharedStore
            accessMode = { VaultAccessMode.current(inDirectory: VaultSharedStorage.directory()) }
        }
        self.appLockSettings = appLockSettings
    }

    /// - Parameter accessMode: How the vault can be opened now. The store is only opened and read while it opens
    ///   without the App Lock Password.
    public init(
        appLockSettings: AppLockSettingsStore = .shared(),
        accessMode: @escaping @Sendable () -> VaultAccessMode,
        makeStore: @escaping StoreFactory,
    ) {
        self.makeStore = makeStore
        plainStore = nil
        self.appLockSettings = appLockSettings
        self.accessMode = accessMode
    }

    /// Whether a HOTP code's next value is got in the app, through a link, rather than by the widget: while the
    /// device key opens the vault, which the widget only reads.
    public nonisolated var advancesHOTPInTheApp: Bool {
        accessMode() == .deviceKey
    }

    /// Whether the widget shows the vault as locked: while the app lock is on, and while only the App Lock Password
    /// opens the vault, or it's being converted, rekeyed or erased. The loader hands out no items then either, so the
    /// widget's actions can't copy or advance a code, and its configuration can't list the vault's items.
    public nonisolated var isLocked: Bool {
        appLockSettings.isEnabled || !accessMode().opensWithoutPassword
    }

    /// All items that are currently eligible to appear in a widget. Hidden,
    /// locked, and search-passphrase items are filtered out — see
    /// `VaultItemWidgetEligibility`.
    public func eligibleItems() async throws -> [VaultItem] {
        guard let store = try await openStore() else { return [] }
        return try await retrieveItems(from: store).filter(VaultItemWidgetEligibility.isEligible)
    }

    /// Fetch a single eligible item by id. Returns `nil` when the item does
    /// not exist or has become ineligible since the user configured the widget.
    /// The two states are indistinguishable to callers by design (manifesto C2).
    public func eligibleItem(id: UUID) async throws -> VaultItem? {
        guard let store = try await openStore() else { return nil }
        return try await eligibleItem(id: id, in: store)
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
    /// This is the only write the widget process performs, read and written through the same store, and only to the
    /// plain store. The plain store is still opened `.openOnly` so a transient open failure can never trigger the
    /// recovery path from an extension (see #526). With the device key, the widget links to the app instead
    /// (`advancesHOTPInTheApp`), so this does nothing, as for a link left from before the password came off.
    public func incrementAndRenderHOTPCode(id: UUID) async throws -> String? {
        guard !advancesHOTPInTheApp,
              let store = try await openStore(),
              let item = try await eligibleItem(id: id, in: store),
              case let .otpCode(otp) = item.item,
              case let .hotp(counter) = otp.type
        else {
            return nil
        }

        let nextCounter = counter + 1
        let code = try HOTPAuthCode(counter: nextCounter, data: otp.data).renderCode()
        try await store.incrementCounter(id: item.id)
        return code
    }

    /// The plain store, guarded, so a HOTP increment can't land in it after the app has started converting it to an
    /// encrypted vault. Or the encrypted file, opened with the device key only to show it, while the password is off.
    private static func makeSharedStore(_ mode: VaultAccessMode) async throws -> any WidgetStore {
        let directory = VaultSharedStorage.directory()
        if mode == .deviceKey {
            return try await VaultStoreSession.openedToShowWithDeviceKey(directory: directory)
        }
        let store = try PersistedLocalVaultStoreFactory(storageDirectory: directory, recoveryMode: .openOnly)
            .makeVaultStoreOrThrow()
        return GuardedPlainVaultStore(store: store, directory: directory)
    }

    /// The store for the vault as it can be opened now, or `nil` while it's locked: nothing opens the plain store once
    /// the vault is encrypted, or while it's being converted, and nothing opens the encrypted file without the device
    /// key.
    private func openStore() async throws -> (any WidgetStore)? {
        guard !appLockSettings.isEnabled else { return nil }
        switch accessMode() {
        case .plain:
            if let plainStore {
                return plainStore
            }
            let store = try await makeStore(.plain)
            plainStore = store
            return store
        case .deviceKey:
            // Opened afresh every time: the store holds the vault in memory, and the app may have changed the file
            // since.
            plainStore = nil
            return try await makeStore(.deviceKey)
        case .password, .unavailable:
            plainStore = nil
            return nil
        }
    }

    private func retrieveItems(from store: any WidgetStore) async throws -> [VaultItem] {
        do {
            return try await store.retrieve(query: .init()).items
        } catch {
            plainStore = nil
            throw error
        }
    }

    private func eligibleItem(id: UUID, in store: any WidgetStore) async throws -> VaultItem? {
        guard let item = try await retrieveItems(from: store).first(where: { $0.id.rawValue == id }) else {
            return nil
        }
        return VaultItemWidgetEligibility.isEligible(item) ? item : nil
    }
}
