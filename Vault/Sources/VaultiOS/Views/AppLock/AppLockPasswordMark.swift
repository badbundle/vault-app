import Foundation
import SwiftUI
import VaultAppIcon

/// The App Lock Password's mark: the vault door from the lock screen that asks for it.
///
/// Setting, changing and managing the password show it too, so they read as the same feature as the lock screen, and
/// the password set there is plainly the one the door asks for. The backup password has a shield instead.
enum AppLockPasswordMark {
    /// The door as the lock screen draws it, in the app icon's colors.
    struct Hero: View {
        /// The door's width and height.
        var size: Double

        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            VaultLockGlyphView(appearance: colorScheme == .dark ? .dark : .light, metrics: .compact)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }

    /// The door in white, for the colored tile of a settings row.
    struct RowIcon: View {
        @ScaledMetric(relativeTo: .body) private var size: Double = 18

        var body: some View {
            VaultLockGlyphView(palette: .monochrome(.white), metrics: .compact)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}
