import Foundation
import VaultCore
import VaultFeed

/// Resolves a QuickType-bar OTP credential request without user
/// interaction. Extracted from `VaultCredentialProviderViewController` so
/// the security-relevant gating — auth-required items and HOTP counters
/// must never be served without interaction — is unit-testable.
@MainActor
struct AutofillOTPCredentialResolver {
    enum Outcome: Equatable {
        /// A rendered TOTP code, safe to return without interaction.
        case code(String)
        /// The item is auth-gated or is an HOTP code (whose counter must
        /// not increment without UI). The system shows the extension UI.
        case userInteractionRequired
        /// The record identifier is missing, malformed, or matches no
        /// unlocked OTP item.
        case notFound
        /// Retrieval or code rendering failed.
        case failure
    }

    private let retrieveItems: () async throws -> VaultRetrievalResult<VaultItem>
    private let copyActionHandler: any VaultItemCopyActionHandler
    private let clock: any EpochClock

    init(
        retrieveItems: @escaping () async throws -> VaultRetrievalResult<VaultItem>,
        copyActionHandler: any VaultItemCopyActionHandler,
        clock: any EpochClock,
    ) {
        self.retrieveItems = retrieveItems
        self.copyActionHandler = copyActionHandler
        self.clock = clock
    }

    func resolve(recordIdentifier: String?) async -> Outcome {
        guard let recordIdentifier, let itemUUID = UUID(uuidString: recordIdentifier) else {
            return .notFound
        }

        do {
            let result = try await retrieveItems()

            guard let vaultItem = result.items.first(where: { $0.id.rawValue == itemUUID }),
                  let otpCode = vaultItem.item.otpCode
            else {
                return .notFound
            }

            // Check if the item requires authentication to access.
            let copyAction = copyActionHandler.textToCopyForVaultItem(id: vaultItem.id)
            if copyAction?.requiresAuthenticationToCopy == true {
                return .userInteractionRequired
            }

            switch otpCode.type {
            case let .totp(period):
                let totpCode = TOTPAuthCode(period: period, data: otpCode.data)
                let epochSeconds = UInt64(clock.currentTime)
                return try .code(totpCode.renderCode(epochSeconds: epochSeconds))
            case .hotp:
                // HOTP codes require user interaction to increment the counter.
                return .userInteractionRequired
            }
        } catch {
            return .failure
        }
    }
}
