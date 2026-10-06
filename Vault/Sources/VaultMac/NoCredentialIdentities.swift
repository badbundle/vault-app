// swiftlint:disable:next no_preconcurrency
@preconcurrency import AuthenticationServices
import Foundation
import VaultCore
import VaultFeed

/// The Mac's credential identity store, which lists codes in Safari's suggestions as QuickType does on iOS: never
/// written, as the App Lock Password is always on (G46).
struct NoCredentialIdentities: VaultOTPAutofillStore {
    func sync(id _: UUID, item _: VaultItem.Write) async throws {}

    func syncAll(items _: [VaultItem]) async throws {}

    func remove(id _: UUID, code _: OTPAuthCode?) async throws {}

    func removeAll() async throws {}

    func getAllIdentities() async throws -> [ASOneTimeCodeCredentialIdentity] {
        []
    }

    func getState() async -> ASCredentialIdentityStoreState {
        await ASCredentialIdentityStore.shared.state()
    }
}
