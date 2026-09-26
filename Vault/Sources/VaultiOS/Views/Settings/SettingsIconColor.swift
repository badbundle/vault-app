import Foundation
import SwiftUI

/// The colors of the row icons on the Settings page.
///
/// Each section has a hue of its own that every row in it shares, so the icons group the rows into their sections at
/// a glance, and each row has its own symbol to tell it apart from the others in its section. A new section gets a hue
/// here that no other section uses.
enum SettingsIconColor {
    static let security = Color.green
    static let clipboard = Color.blue
    static let danger = Color.red
}
