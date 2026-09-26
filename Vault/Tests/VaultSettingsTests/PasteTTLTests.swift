import Foundation
import Testing
import VaultSettings

struct PasteTTLTests {
    @Test
    func localizedName_withoutDurationIsNever() {
        #expect(PasteTTL(duration: nil).localizedName == "Never")
    }

    @Test(arguments: [
        (30.0, "30 seconds"),
        (60.0, "1 minute"),
        (60.0 * 2, "2 minutes"),
        (60.0 * 30, "30 minutes"),
    ])
    func localizedName_spellsOutDuration(duration: Double, expected: String) {
        #expect(PasteTTL(duration: duration).localizedName == expected)
    }
}
