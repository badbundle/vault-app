import Foundation
import FoundationExtensions
import VaultCore

/// A code as Spotlight shows it: its site's name, and nothing else (VAULT-72).
///
/// Spotlight can be searched without opening Vault, so it only ever gets what Vault itself shows to anyone who opens
/// it, and less. It's only kept while App Lock is off, when nothing stands between the unlocked phone and the vault
/// anyway (see `SpotlightCode.codes(in:isTurnedOn:isAppLockOn:)`). Even then:
///
/// - Only codes: never notes, recovery phrases or encrypted items.
/// - Only codes the feed shows as they are: never one that's hidden until searched for, locked, or that Vault's own
///   search can't find.
/// - Only the site's name: never the account name, which is often an email address, nor anything else.
///
/// A code with a killphrase is shown like any other. Leaving it out would let someone compare Spotlight with the feed
/// and find the codes with one (MANIFESTO C5).
public struct SpotlightCode: Equatable, Hashable, Sendable {
    public var id: Identifier<VaultItem>
    /// The site the code is for, as its card in the feed names it.
    public var name: String

    public init(id: Identifier<VaultItem>, name: String) {
        self.id = id
        self.name = name
    }
}

extension SpotlightCode {
    /// What Spotlight should hold now: nothing unless the user has turned it on, and nothing while App Lock is on,
    /// whatever `items` holds.
    ///
    /// - Parameters:
    ///   - items: Every item the open vault shows without a search, however the feed is filtered.
    ///   - isTurnedOn: Whether the user has turned on showing codes in Spotlight.
    ///   - isAppLockOn: Whether App Lock, or the App Lock Password, is on.
    public static func codes(in items: [VaultItem], isTurnedOn: Bool, isAppLockOn: Bool) -> [SpotlightCode] {
        guard isTurnedOn, !isAppLockOn else { return [] }
        return items.compactMap(SpotlightCode.init(item:))
    }

    /// The code as Spotlight shows it, or `nil` if Spotlight mustn't show it.
    init?(item: VaultItem) {
        guard
            case let .otpCode(code) = item.item,
            item.metadata.visibility == .always,
            item.metadata.lockState == .notLocked,
            item.metadata.searchableLevel.allowsFindingByName
        else { return nil }
        let name = code.data.issuer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        self.init(id: item.id, name: name)
    }
}

extension VaultItemSearchableLevel {
    /// Whether Vault's own search finds the item by its name.
    fileprivate var allowsFindingByName: Bool {
        switch self {
        case .full, .onlyTitle: true
        case .none, .onlyPassphrase: false
        }
    }
}
