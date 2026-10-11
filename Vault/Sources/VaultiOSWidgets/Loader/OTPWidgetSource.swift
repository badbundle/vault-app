import Foundation
import VaultFeed

/// Where the widgets get their codes, which is all that differs between the iOS widgets and the Mac's: everything else
/// they share.
///
/// - **iOS** opens the vault in the widget extension (`WidgetVaultLoader`): while App Lock and the App Lock Password
///   are off, it shows codes, and otherwise it shows Vault as locked (G44).
/// - **The Mac**'s App Lock Password is always on, and the widget extension never opens the vault. It shows the codes
///   the app hands it while the vault's unlocked, and nothing else (`WidgetCodeHandoffStore`, G98).
public enum OTPWidgetSource: Sendable {
    case vault(WidgetVaultLoader)
    case handoff(WidgetCodeHandoffStore)

    /// This platform's.
    public static var platform: OTPWidgetSource {
        #if os(macOS)
        .handoff(WidgetCodeHandoffStore())
        #else
        .vault(.shared)
        #endif
    }

    /// The codes a widget's settings can list, which are none while Vault's locked.
    func entities(now: Date) async -> [OTPWidgetItemEntity] {
        switch self {
        case let .vault(loader):
            guard let items = try? await loader.eligibleItems() else { return [] }
            return items.compactMap(OTPWidgetItemEntity.init(item:))
        case let .handoff(store):
            return store.current(at: now)?.items.map(OTPWidgetItemEntity.init(item:)) ?? []
        }
    }

    /// The time-based code to copy now, if the widget may still show it.
    func currentTOTPCode(itemID: UUID, now: Date) async throws -> String? {
        switch self {
        case let .vault(loader):
            try await loader.currentTOTPCode(id: itemID, date: now)
        case let .handoff(store):
            store.current(at: now)?.code(itemID: itemID, at: now)
        }
    }

    /// Advances a counter-based code and returns its next one. Never from the Mac's widgets, which are given no
    /// counter-based codes.
    func incrementAndRenderHOTPCode(itemID: UUID) async throws -> String? {
        switch self {
        case let .vault(loader):
            try await loader.incrementAndRenderHOTPCode(id: itemID)
        case .handoff:
            nil
        }
    }
}
