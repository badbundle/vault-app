import Foundation

// swiftlint:disable:next no_preconcurrency
@preconcurrency import AuthenticationServices

/// Keeps the QuickType identity store empty while only the App Lock Password opens the vault.
///
/// The identity store lives outside the app's sandbox and holds the issuer and account name of every code it
/// suggests, readable without the password. So while the vault needs the password (or is being converted, rekeyed or
/// erased), nothing is written to it: a sync of one item does nothing, and a sync of everything empties it instead.
/// Removing identities is always allowed. While the vault opens without the password, plain or with the device key,
/// everything goes through to `base`, so QuickType works as it always has.
///
/// The password can come on while a write is underway, after the app has emptied the store for it. So each write
/// checks again once it's done, and empties the store if the password's on by then.
///
/// See "Widgets, AutoFill and QuickType" in `docs/on-device-encryption.md`.
public final class PasswordlessOTPAutofillStore: VaultOTPAutofillStore {
    private let base: any VaultOTPAutofillStore
    private let opensWithoutPassword: @Sendable () -> Bool

    /// - Parameter opensWithoutPassword: Whether the vault opens without the App Lock Password right now
    ///   (`VaultAccessMode.opensWithoutPassword`). Asked before every write, since the mode can change while the app
    ///   runs.
    public init(base: any VaultOTPAutofillStore, opensWithoutPassword: @escaping @Sendable () -> Bool) {
        self.base = base
        self.opensWithoutPassword = opensWithoutPassword
    }

    public func sync(id: UUID, item: VaultItem.Write) async throws {
        guard opensWithoutPassword() else { return }
        try await base.sync(id: id, item: item)
        try await emptyIfThePasswordCameOn()
    }

    public func syncAll(items: [VaultItem]) async throws {
        if opensWithoutPassword() {
            try await base.syncAll(items: items)
            try await emptyIfThePasswordCameOn()
        } else {
            try await base.removeAll()
        }
    }

    /// Empties the store if the password came on while a write was underway. The mode changes before the app empties
    /// the store for it, so a write that landed after that empty is always seen here.
    private func emptyIfThePasswordCameOn() async throws {
        guard !opensWithoutPassword() else { return }
        try await base.removeAll()
    }

    public func remove(id: UUID, code: OTPAuthCode?) async throws {
        try await base.remove(id: id, code: code)
    }

    public func removeAll() async throws {
        try await base.removeAll()
    }

    public func getAllIdentities() async throws -> [ASOneTimeCodeCredentialIdentity] {
        try await base.getAllIdentities()
    }

    public func getState() async -> ASCredentialIdentityStoreState {
        await base.getState()
    }
}
