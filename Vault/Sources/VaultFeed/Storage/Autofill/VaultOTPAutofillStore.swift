import Foundation

// swiftlint:disable:next no_preconcurrency
@preconcurrency import AuthenticationServices
import VaultCore

/// The store which is used for autofilling OTP credentials on websites (iOS system integration).
///
/// This is required by the system in order to display offer up suggestions for autofilling.
/// The app extension can then be used to actually retrieve the value for the code (and the logic for this is managed
/// inside the extension).
///
/// ## recordIdentifier Policy
/// All credential identities use the VaultItem's UUID as the recordIdentifier (UUID.uuidString).
/// This provides a unique, stable identifier for each OTP credential and enables individual
/// management (add, update, remove) without affecting other credentials.
///
/// @mockable
public protocol VaultOTPAutofillStore: Sendable {
    /// Syncs a VaultItem to the autofill store, as it's written.
    /// If the item is an OTP code, it will be added/updated. Otherwise, this is a no-op.
    /// Items hidden with passphrase (requiresSearchPassphrase) and locked items will not be added to autofill.
    func sync(id: UUID, item: VaultItem.Write) async throws

    /// Syncs all vault items to the autofill store.
    /// Removes all existing items and repopulates with all OTP items from the vault.
    /// Items hidden with passphrase (requiresSearchPassphrase) and locked items will not be added to autofill.
    func syncAll(items: [VaultItem]) async throws

    /// Removes a specific OTP credential identity by VaultItem UUID.
    /// Safe to call even if the item is not in the autofill store.
    /// - Parameters:
    ///   - id: The UUID of the vault item
    ///   - code: Optional OTP code data to help match the identity. If nil, will attempt removal with empty fields.
    func remove(id: UUID, code: OTPAuthCode?) async throws

    /// Removes all OTP credential identities from the store.
    func removeAll() async throws

    /// Gets all OTP credential identities currently in the store.
    /// - Throws: `CredentialIdentityStoreError.storeDisabled` if AutoFill is not enabled
    func getAllIdentities() async throws -> [ASOneTimeCodeCredentialIdentity]

    /// Gets the current state of the credential identity store.
    func getState() async -> ASCredentialIdentityStoreState
}

public final class VaultOTPAutofillStoreImpl: VaultOTPAutofillStore {
    private let store: any CredentialIdentityStore

    public init(store: any CredentialIdentityStore) {
        self.store = store
    }

    public func sync(id: UUID, item: VaultItem.Write) async throws {
        guard let otpCode = item.item.otpCode else {
            // Not an OTP item, remove from autofill store if present
            try await remove(id: id, code: nil)
            return
        }

        // Check if item is hidden with passphrase
        let viewConfig = VaultItemViewConfiguration(visibility: item.visibility, searchableLevel: item.searchableLevel)
        if viewConfig == .requiresSearchPassphrase {
            // Hidden items should not appear in autofill, remove if present
            try await remove(id: id, code: otpCode)
            return
        }

        // Locked items aren't suggested either: their site and account stay behind the lock, as in the feed.
        if item.lockState.isLocked {
            try await remove(id: id, code: otpCode)
            return
        }

        // Check if item has QuickType disabled
        if !item.showInQuickType {
            try await remove(id: id, code: otpCode)
            return
        }

        // Remove existing identity first to ensure updates are reflected
        // saveCredentialIdentities does not update existing identities, only inserts new ones
        try await remove(id: id, code: otpCode)

        let identity = ASOneTimeCodeCredentialIdentity(
            serviceIdentifier: ASCredentialServiceIdentifier(
                identifier: otpCode.data.issuer,
                type: .domain,
            ),
            label: otpCode.data.accountName,
            recordIdentifier: id.uuidString,
        )
        try await store.saveCredentialIdentities([identity])
    }

    public func syncAll(items: [VaultItem]) async throws {
        // Clear all existing identities
        try await store.removeAllCredentialIdentities()

        // Build identities for all OTP items that are not hidden with passphrase
        let identities = items.compactMap { item -> ASOneTimeCodeCredentialIdentity? in
            guard let otpCode = item.item.otpCode else { return nil }

            // Check if item is hidden with passphrase
            let viewConfig = VaultItemViewConfiguration(
                visibility: item.metadata.visibility,
                searchableLevel: item.metadata.searchableLevel,
            )
            if viewConfig == .requiresSearchPassphrase {
                // Hidden items should not appear in autofill
                return nil
            }

            // Locked items aren't suggested either
            if item.metadata.lockState.isLocked {
                return nil
            }

            // Check if item has QuickType disabled
            if !item.metadata.showInQuickType {
                return nil
            }

            return ASOneTimeCodeCredentialIdentity(
                serviceIdentifier: ASCredentialServiceIdentifier(
                    identifier: otpCode.data.issuer,
                    type: .domain,
                ),
                label: otpCode.data.accountName,
                recordIdentifier: item.id.rawValue.uuidString,
            )
        }

        // Only save if there are identities to add
        if !identities.isEmpty {
            try await store.saveCredentialIdentities(identities)
        }
    }

    public func remove(id: UUID, code: OTPAuthCode?) async throws {
        // Create identity for removal
        // If we have the code data, use it to ensure proper matching
        // Otherwise use empty values and hope recordIdentifier alone is enough
        let identity = ASOneTimeCodeCredentialIdentity(
            serviceIdentifier: ASCredentialServiceIdentifier(
                identifier: code?.data.issuer ?? "",
                type: .domain,
            ),
            label: code?.data.accountName ?? "",
            recordIdentifier: id.uuidString,
        )
        try await store.removeCredentialIdentities([identity])
    }

    public func removeAll() async throws {
        try await store.removeAllCredentialIdentities()
    }

    public func getAllIdentities() async throws -> [ASOneTimeCodeCredentialIdentity] {
        let identities = try await store.getCredentialIdentities()
        return identities.compactMap { $0 as? ASOneTimeCodeCredentialIdentity }
    }

    public func getState() async -> ASCredentialIdentityStoreState {
        await store.getState()
    }
}
