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
        /// The app lock is on, only the App Lock Password opens the vault, the
        /// item is auth-gated, or it's an HOTP code (whose counter must not
        /// increment without UI). The system shows the extension UI.
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
    private let isAppLockEnabled: Bool
    private let accessMode: VaultAccessMode

    /// - Parameter accessMode: How the vault can be opened now. A plain vault,
    ///   or one the device key opens, is read as it always has been; one only
    ///   the App Lock Password opens isn't read at all.
    init(
        retrieveItems: @escaping () async throws -> VaultRetrievalResult<VaultItem>,
        copyActionHandler: any VaultItemCopyActionHandler,
        clock: any EpochClock,
        isAppLockEnabled: Bool,
        accessMode: VaultAccessMode,
    ) {
        self.retrieveItems = retrieveItems
        self.copyActionHandler = copyActionHandler
        self.clock = clock
        self.isAppLockEnabled = isAppLockEnabled
        self.accessMode = accessMode
    }

    func resolve(recordIdentifier: String?) async -> Outcome {
        // With the app lock on, or only the password opening the vault, no
        // code leaves the vault until the user has unlocked it in the
        // extension's UI, with the password if it's on. The vault isn't even
        // read.
        guard !isAppLockEnabled, accessMode.opensWithoutPassword else {
            return .userInteractionRequired
        }

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
