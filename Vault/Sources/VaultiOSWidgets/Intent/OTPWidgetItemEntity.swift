import AppIntents
import Foundation
import VaultFeed

/// User-selectable widget item shown in the widget's edit sheet.
///
/// The list of entities exposed by `Query` is **filtered to eligible items
/// only** (see `VaultItemWidgetEligibility`). Items that the user has marked
/// hidden, locked, or search-passphrase-gated never appear here.
public struct OTPWidgetItemEntity: AppEntity, Identifiable, Hashable {
    public var id: UUID
    public var issuer: String
    public var accountName: String

    public init(id: UUID, issuer: String, accountName: String) {
        self.id = id
        self.issuer = issuer
        self.accountName = accountName
    }

    /// The vault's code, or `nil` if the item isn't a code.
    init?(item: VaultItem) {
        guard case let .otpCode(otp) = item.item else { return nil }
        self.init(id: item.id.rawValue, issuer: otp.data.issuer, accountName: otp.data.accountName)
    }

    /// A code the Mac app handed over.
    init(item: WidgetCodeHandoff.Item) {
        self.init(id: item.id, issuer: item.issuer, accountName: item.accountName)
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(displayTitle)",
            subtitle: accountName.isEmpty ? nil : "\(accountName)",
        )
    }

    private var displayTitle: String {
        issuer.isEmpty ? accountName : issuer
    }

    public nonisolated static let typeDisplayRepresentation: TypeDisplayRepresentation = .init(name: "OTP Code")

    public nonisolated static let defaultQuery = OTPWidgetItemEntityQuery()
}

/// Provides the dynamic options shown in the widget configuration picker.
/// Only eligible OTP items are returned — see `VaultItemWidgetEligibility`.
/// While Vault is locked, it lists none (G44, G98).
public struct OTPWidgetItemEntityQuery: EntityQuery, Sendable {
    public typealias Entity = OTPWidgetItemEntity

    private let source: OTPWidgetSource

    public init() {
        source = .platform
    }

    public init(loader: WidgetVaultLoader) {
        source = .vault(loader)
    }

    public init(handoff: WidgetCodeHandoffStore) {
        source = .handoff(handoff)
    }

    public func entities(for identifiers: [OTPWidgetItemEntity.ID]) async throws -> [OTPWidgetItemEntity] {
        let lookup = Set(identifiers)
        return await source.entities(now: Date()).filter { lookup.contains($0.id) }
    }

    public func suggestedEntities() async throws -> [OTPWidgetItemEntity] {
        await source.entities(now: Date())
    }

    public func defaultResult() async -> OTPWidgetItemEntity? {
        try? await suggestedEntities().first
    }
}
