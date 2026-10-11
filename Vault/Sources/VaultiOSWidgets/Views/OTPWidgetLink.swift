import Foundation
import SwiftUI
import VaultiOSShared

/// Where tapping part of a widget goes in the app. On iOS, Vault's own links (`WidgetDeepLink`). The Mac app has no
/// URL scheme (docs/mac-app.md, decision 2), so there's none: clicking a Mac widget opens Vault, as for any widget.
enum OTPWidgetLink {
    /// Opens the item in the app.
    static func itemDetail(itemID: UUID) -> URL? {
        #if os(macOS)
        nil
        #else
        WidgetDeepLink.openItemDetail(itemID: itemID)
        #endif
    }

    /// Opens the app and advances a counter-based code there.
    static func hotpIncrement(itemID: UUID) -> URL? {
        #if os(macOS)
        nil
        #else
        WidgetDeepLink.hotpIncrement(itemID: itemID)
        #endif
    }
}

extension Color {
    /// An empty timer bar's track.
    static var widgetTrack: Color {
        #if canImport(UIKit)
        Color(.quaternarySystemFill)
        #else
        Color(nsColor: .quaternarySystemFill)
        #endif
    }
}
