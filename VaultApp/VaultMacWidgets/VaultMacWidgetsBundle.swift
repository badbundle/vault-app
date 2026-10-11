import SwiftUI
import VaultiOSWidgets
import WidgetKit

/// The Mac's widgets, the same as the iOS app's: everything they do is in `VaultiOSWidgets`. They only show the codes
/// the unlocked app hands them, and never open the vault (docs/mac-app.md, "Widgets").
@main
struct VaultMacWidgetsBundle: WidgetBundle {
    var body: some Widget {
        OTPWidget()
    }

    init() {
        _ = OTPWidgetIntent.self
        _ = OTPWidgetItemEntity.self
    }
}
