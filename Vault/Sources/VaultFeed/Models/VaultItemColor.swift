import CryptoEngine
import Foundation
import FoundationExtensions

public struct VaultItemColor: Equatable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

extension VaultItemColor: Digestable {
    public var digestableData: some Encodable {
        struct DigestData: Encodable {
            var red, green, blue: Double
        }
        return DigestData(red: red, green: green, blue: blue)
    }
}

extension VaultItemColor {
    /// A sensible placeholder color to use.
    public static var `default`: VaultItemColor {
        .gray
    }

    public static var tagDefault: VaultItemColor {
        .init(red: 0, green: 0.47, blue: 0.68)
    }

    public static var gray: VaultItemColor {
        VaultItemColor(red: 0.5, green: 0.5, blue: 0.5)
    }

    public static var black: VaultItemColor {
        VaultItemColor(red: 0, green: 0, blue: 0)
    }

    public static var white: VaultItemColor {
        VaultItemColor(red: 1, green: 1, blue: 1)
    }

    public static func random() -> VaultItemColor {
        VaultItemColor(
            red: Double.random(in: 0 ... 1),
            green: Double.random(in: 0 ... 1),
            blue: Double.random(in: 0 ... 1),
        )
    }

    public func brighten(amount: Double) -> VaultItemColor {
        // Standard brightness components for each channel, based on the human eye.
        VaultItemColor(
            red: (red + amount * 0.299).clamped(to: 0 ... 1),
            green: (green + amount * 0.587).clamped(to: 0 ... 1),
            blue: (blue + amount * 0.114).clamped(to: 0 ... 1),
        )
    }
}
