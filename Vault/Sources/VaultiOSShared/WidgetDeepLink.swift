import Foundation

/// Deep-link URLs that the widget hands back to the main app via `widgetURL(_:)`.
///
/// The main app's `onOpenURL` must understand these schemes. Centralised
/// here so the widget and the app's URL handler agree on the format without
/// passing strings through documentation.
public enum WidgetDeepLink {
    /// URL scheme. Must match the `CFBundleURLSchemes` entry in the main
    /// app's `Info.plist`.
    public static let scheme = "vault"

    /// Tap target on HOTP widgets: opens the app and advances the counter
    /// for the given item.
    public static func hotpIncrement(itemID: UUID) -> URL {
        URL(string: "\(scheme)://otp/\(itemID.uuidString)/increment").unsafelyUnwrapped
    }

    /// Opens the main app directly to an OTP item's detail screen.
    public static func openItemDetail(itemID: UUID) -> URL {
        URL(string: "\(scheme)://otp/\(itemID.uuidString)/detail").unsafelyUnwrapped
    }

    /// Parses a URL produced by one of the constructors above. Returns nil
    /// if the URL does not match a known shape.
    public static func parse(_ url: URL) -> Action? {
        guard url.scheme == scheme else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        switch (url.host, parts) {
        case let ("otp", components) where components.count == 2 && components[1] == "increment":
            guard let id = UUID(uuidString: components[0]) else { return nil }
            return .incrementHOTP(itemID: id)
        case let ("otp", components) where components.count == 2 && components[1] == "detail":
            guard let id = UUID(uuidString: components[0]) else { return nil }
            return .openItemDetail(itemID: id)
        default:
            return nil
        }
    }

    public enum Action: Equatable, Sendable {
        case incrementHOTP(itemID: UUID)
        case openItemDetail(itemID: UUID)
    }
}
