import Foundation

// swiftlint:disable:next no_preconcurrency
@preconcurrency import AuthenticationServices

/// Keeps the QuickType identity store empty while the vault is encrypted with the App Lock Password.
///
/// The identity store lives outside the app's sandbox and holds the issuer and account name of every code it
/// suggests, readable without the password. So while the vault isn't plain (encrypted, or being converted), nothing
/// is written to it: a sync of one item does nothing, and a sync of everything empties it instead. Removing
/// identities is always allowed. With a plain vault, everything goes through to `base` as before.
///
/// See "Widgets, AutoFill and QuickType" in `docs/on-device-encryption.md`.
public final class PlainVaultOnlyOTPAutofillStore: VaultOTPAutofillStore {
    private let base: any VaultOTPAutofillStore
    private let isVaultPlain: @Sendable () -> Bool

    /// - Parameter isVaultPlain: Whether the vault is in the plain store right now, with no change of mode underway.
    ///   Asked before every write, since the mode can change while the app runs.
    public init(base: any VaultOTPAutofillStore, isVaultPlain: @escaping @Sendable () -> Bool) {
        self.base = base
        self.isVaultPlain = isVaultPlain
    }

    public func sync(
        id: UUID,
        item: VaultItem.Payload,
        visibility: VaultItemVisibility,
        searchableLevel: VaultItemSearchableLevel,
        showInQuickType: Bool,
    ) async throws {
        guard isVaultPlain() else { return }
        try await base.sync(
            id: id,
            item: item,
            visibility: visibility,
            searchableLevel: searchableLevel,
            showInQuickType: showInQuickType,
        )
    }

    public func syncAll(items: [VaultItem]) async throws {
        if isVaultPlain() {
            try await base.syncAll(items: items)
        } else {
            try await base.removeAll()
        }
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
