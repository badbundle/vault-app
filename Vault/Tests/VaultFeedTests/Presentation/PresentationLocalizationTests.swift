import Foundation
import TestHelpers
import Testing
@testable import VaultFeed

struct PresentationLocalizationTests {
    @Test
    func localizedStrings_haveKeysAndValuesForAllSupportedLocalizations() {
        // Not `.module`: this test target has a bundle of its own, for its fixtures.
        expectLocalizedKeyAndValuesExist(in: VaultFeedAssets.bundle, "VaultFeed")
    }

    @Test
    func localizedStrings_getsKeyFromTable() {
        let value = localized(key: "TEST_KEY_DONT_CHANGE")
        #expect(value == "TEST_VALUE_DONT_CHANGE")
    }
}
