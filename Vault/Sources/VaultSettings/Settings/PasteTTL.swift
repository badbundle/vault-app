import Foundation
import FoundationExtensions
import VaultCore

public struct PasteTTL: Equatable, Hashable, Codable, Sendable {
    public let duration: Double?

    public init(duration: Double?) {
        self.duration = duration
    }
}

extension PasteTTL: Identifiable {
    public var id: Double {
        duration ?? -1
    }
}

extension PasteTTL {
    /// Copied values are cleared after a minute unless the user chooses otherwise (MANIFESTO C7).
    ///
    /// Only a choice made in Settings is ever stored, so changing this reaches everyone who never chose, and
    /// anyone who chose "Never" keeps it.
    public static let `default`: PasteTTL = .init(duration: 60)

    public static let defaultOptions: [PasteTTL] = [
        .init(duration: nil),
        .init(duration: 30),
        .init(duration: 60),
        .init(duration: 60 * 2),
        .init(duration: 60 * 5),
        .init(duration: 60 * 10),
        .init(duration: 60 * 30),
    ]
}

extension PasteTTL {
    /// Where the Clear Clipboard setting is stored. The app keeps it in the defaults it shares with its extensions.
    static var storageKey: Key<PasteTTL> {
        Key(VaultIdentifiers.Preferences.General.settingsPasteTTL)
    }

    /// The Clear Clipboard setting stored in `defaults`, for an extension that copies a value but has no
    /// `LocalSettings` of its own.
    @MainActor
    public static func stored(in defaults: Defaults) -> PasteTTL {
        defaults.get(for: storageKey) ?? .default
    }

    /// When a value copied at `date` should be cleared from the clipboard, or `nil` to keep it.
    public func expiryDate(copiedAt date: Date) -> Date? {
        duration.map { date.addingTimeInterval($0) }
    }
}

extension PasteTTL {
    public var localizedName: String {
        guard let duration else {
            return localized(key: "pasteTTL.none")
        }
        let formatter = DateComponentsFormatter()
        // Spelled out: "1 minute" reads better next to the setting than "1m", which VoiceOver reads as meters.
        formatter.unitsStyle = .full
        formatter.allowedUnits = [.minute, .second]
        return formatter.string(from: duration) ?? "?"
    }
}
