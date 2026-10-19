// swiftlint:disable:next no_preconcurrency
@preconcurrency import AuthenticationServices
import Foundation
import VaultCore
import VaultFeed

/// The Mac's credential identity store, which lists codes in Safari's suggestions as QuickType does on iOS: never
/// written, as the App Lock Password is always on (G46).
public struct NoCredentialIdentities: VaultOTPAutofillStore {
    public init() {}

    public func sync(id _: UUID, item _: VaultItem.Write) async throws {}

    public func syncAll(items _: [VaultItem]) async throws {}

    public func remove(id _: UUID, code _: OTPAuthCode?) async throws {}

    public func removeAll() async throws {}

    public func getAllIdentities() async throws -> [ASOneTimeCodeCredentialIdentity] {
        []
    }

    public func getState() async -> ASCredentialIdentityStoreState {
        await ASCredentialIdentityStore.shared.state()
    }
}
