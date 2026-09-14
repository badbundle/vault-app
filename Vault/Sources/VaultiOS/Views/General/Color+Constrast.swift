import Foundation
import SwiftUI

extension Color {
    var percievedBrightness: Double {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        if UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            // Calculate brightness using standard formula
            return 0.299 * Double(red) + 0.587 * Double(green) + 0.114 * Double(blue)
        }

        return 0.0
    }

    var isPercievedLight: Bool {
        percievedBrightness > 0.9
    }

    var isPercievedDark: Bool {
        percievedBrightness < 0.1
    }
}
