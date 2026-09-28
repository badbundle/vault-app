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
public struct OTPWidgetItemEntityQuery: EntityQuery, Sendable {
    public typealias Entity = OTPWidgetItemEntity

    private let loader: WidgetVaultLoader

    public init() {
        loader = .shared
    }

    public init(loader: WidgetVaultLoader) {
        self.loader = loader
    }

    public func entities(for identifiers: [OTPWidgetItemEntity.ID]) async throws -> [OTPWidgetItemEntity] {
        let lookup = Set(identifiers)
        guard let items = try? await loader.eligibleItems() else { return [] }
        return items
            .filter { lookup.contains($0.id.rawValue) }
            .compactMap(Self.makeEntity(from:))
    }

    public func suggestedEntities() async throws -> [OTPWidgetItemEntity] {
        guard let items = try? await loader.eligibleItems() else { return [] }
        return items.compactMap(Self.makeEntity(from:))
    }

    public func defaultResult() async -> OTPWidgetItemEntity? {
        try? await suggestedEntities().first
    }

    private static func makeEntity(from item: VaultItem) -> OTPWidgetItemEntity? {
        guard case let .otpCode(otp) = item.item else { return nil }
        return OTPWidgetItemEntity(
            id: item.id.rawValue,
            issuer: otp.data.issuer,
            accountName: otp.data.accountName,
        )
    }
}
