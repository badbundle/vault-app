import Foundation

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
    public static let `default`: PasteTTL = .init(duration: nil)

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
