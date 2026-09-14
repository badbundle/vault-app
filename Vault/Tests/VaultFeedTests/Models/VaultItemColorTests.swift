import Foundation
import Testing
@testable import VaultFeed

struct VaultItemColorTests {
    @Test
    func brighten_appliesEachChannelsOwnLuminanceWeight() {
        let color = VaultItemColor(red: 0.1, green: 0.2, blue: 0.3)

        let result = color.brighten(amount: 1)

        // Each channel is offset by its own coefficient, not another channel's.
        #expect(abs(result.red - (0.1 + 0.299)) < 0.0001)
        #expect(abs(result.green - (0.2 + 0.587)) < 0.0001)
        #expect(abs(result.blue - (0.3 + 0.114)) < 0.0001)
    }

    /// Regression cover for a channel swap: `green` was derived from `blue` and `blue` from
    /// `green`, so brightening rotated the hue instead of lightening it.
    @Test
    func brighten_doesNotSwapGreenAndBlue() {
        let color = VaultItemColor(red: 0, green: 1, blue: 0)

        let result = color.brighten(amount: 0)

        #expect(result == color)
    }

    @Test
    func brighten_isMonotonicPerChannel() {
        let color = VaultItemColor(red: 0.4, green: 0.4, blue: 0.4)

        let brighter = color.brighten(amount: 0.5)
        let darker = color.brighten(amount: -0.5)

        #expect(brighter.red > color.red)
        #expect(brighter.green > color.green)
        #expect(brighter.blue > color.blue)
        #expect(darker.red < color.red)
        #expect(darker.green < color.green)
        #expect(darker.blue < color.blue)
    }

    @Test
    func brighten_clampsToUnitRange() {
        let light = VaultItemColor(red: 0.95, green: 0.95, blue: 0.95)
        let dark = VaultItemColor(red: 0.05, green: 0.05, blue: 0.05)

        let overBright = light.brighten(amount: 5)
        let overDark = dark.brighten(amount: -5)

        #expect(overBright.red == 1)
        #expect(overBright.green == 1)
        #expect(overBright.blue == 1)
        #expect(overDark.red == 0)
        #expect(overDark.green == 0)
        #expect(overDark.blue == 0)
    }
}
