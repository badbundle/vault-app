import Foundation
import FoundationExtensions

public enum VaultItemViewConfiguration: Equatable, Hashable, CaseIterable, IdentifiableSelf, Sendable {
    /// The item is always visible and searchable.
    case alwaysVisible
    /// The item is only visible when searching and requires a passphrase to be entered.
    case requiresSearchPassphrase
}

// MARK: - Interop

extension VaultItemViewConfiguration {
    public init(visibility: VaultItemVisibility, searchableLevel: VaultItemSearchableLevel) {
        switch visibility {
        case .always: self = .alwaysVisible
        case .onlySearch:
            switch searchableLevel {
            case .full, .onlyTitle, .none: self = .alwaysVisible
            case .onlyPassphrase: self = .requiresSearchPassphrase
            }
        }
    }

    public var visibility: VaultItemVisibility {
        switch self {
        case .alwaysVisible: .always
        case .requiresSearchPassphrase: .onlySearch
        }
    }

    public var searchableLevel: VaultItemSearchableLevel {
        switch self {
        case .alwaysVisible: .full
        case .requiresSearchPassphrase: .onlyPassphrase
        }
    }

    public var isEnabled: Bool {
        get {
            switch self {
            case .alwaysVisible: false
            case .requiresSearchPassphrase: true
            }
        }
        set {
            self = newValue ? .requiresSearchPassphrase : .alwaysVisible
        }
    }
}

// MARK: - Localization

extension VaultItemViewConfiguration {
    public var systemIconName: String {
        switch self {
        case .alwaysVisible: "eye"
        case .requiresSearchPassphrase: "eye.slash"
        }
    }

    public var localizedTitle: String {
        switch self {
        case .alwaysVisible: localized(key: "vaultItemViewConfiguration.alwaysVisible.title")
        case .requiresSearchPassphrase: localized(
                key: "vaultItemViewConfiguration.requiresSearchPassphrase.title",
            )
        }
    }
}
