import Foundation

// swiftlint:disable:next no_preconcurrency
@preconcurrency import AuthenticationServices

public enum CredentialIdentityStoreError: Error {
    case storeDisabled
    case storeNotSupported
}

/// Thin wrapper around ASCredentialIdentityStore, allowing for mocking and injection.
///
/// @mockable
public protocol CredentialIdentityStore: Sendable {
    func replaceCredentialIdentities(_ newCredentials: [any ASCredentialIdentity]) async throws
    func saveCredentialIdentities(_ newCredentials: [any ASCredentialIdentity]) async throws
    func removeCredentialIdentities(_ credentials: [any ASCredentialIdentity]) async throws
    func removeAllCredentialIdentities() async throws
    func getCredentialIdentities() async throws -> [any ASCredentialIdentity]
    func getState() async -> ASCredentialIdentityStoreState
}

/// Real implementation that delegates to ASCredentialIdentityStore.shared
/// For more information on how this works, see: https://nonstrict.eu/wwdcindex/wwdc2018/721
public final class RealCredentialIdentityStore: CredentialIdentityStore {
    private let store = ASCredentialIdentityStore.shared

    public init() {}

    public func replaceCredentialIdentities(_ newCredentials: [any ASCredentialIdentity]) async throws {
        try await store.replaceCredentialIdentities(newCredentials)
    }

    public func saveCredentialIdentities(_ newCredentials: [any ASCredentialIdentity]) async throws {
        try await store.saveCredentialIdentities(newCredentials)
    }

    public func removeCredentialIdentities(_ credentials: [any ASCredentialIdentity]) async throws {
        try await store.removeCredentialIdentities(credentials)
    }

    public func removeAllCredentialIdentities() async throws {
        // With Vault turned off as an AutoFill provider the store refuses changes, and it holds nothing of ours to
        // remove: the system clears a provider's identities when it's turned off.
        guard await store.state().isEnabled else { return }
        try await store.removeAllCredentialIdentities()
    }

    public func getCredentialIdentities() async throws(CredentialIdentityStoreError) -> [any ASCredentialIdentity] {
        let state = await store.state()

        guard state.isEnabled else {
            throw CredentialIdentityStoreError.storeDisabled
        }

        // Note: ASCredentialIdentityStore.credentialIdentities() always returns an empty array
        // when called from the app target or extension. Individual credentials are managed by
        // the system and cannot be enumerated by the app. We can only read the store state
        // (isEnabled, supportsIncrementalUpdates) and modify credentials via save/remove operations.
        return []
    }

    public func getState() async -> ASCredentialIdentityStoreState {
        await store.state()
    }
}
